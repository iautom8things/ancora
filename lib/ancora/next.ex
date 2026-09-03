defmodule Ancora.Next do
  @moduledoc """
  Classifies the current change set and reports the next spec-led action.

  Classification and reconciliation labels are kept byte-for-byte compatible
  with specled_ex because agent workflows consume them as an API.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.RunContext
  alias Ancora.Gate.Preflight
  alias Ancora.PolicyFiles
  alias Ancora.Status

  @spec build(Path.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def build(root, opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)
    base = Keyword.get(opts, :since) || Keyword.get(opts, :base)

    with {:ok, preflight} <- Preflight.run(root, base: base),
         {:ok, change_set} <- change_set(preflight.root, preflight.base),
         {:ok, status} <- Status.build(root, opts) do
      {:ok, report(preflight.base, change_set, status.subjects, opts)}
    end
  end

  defp change_set(root, base) do
    with {:ok, context} <- RunContext.start(root, base) do
      try do
        ChangeSet.compute(context)
      after
        RunContext.stop(context)
      end
    end
  end

  defp report(base, change_set, subjects, opts) do
    changed_files = ChangeSet.paths(change_set)
    policy_files = Enum.filter(changed_files, &PolicyFiles.policy_target?/1)
    changed_subject_ids = changed_subject_ids(subjects, changed_files)
    impacted = impacted_subjects(subjects, policy_files, changed_subject_ids)
    uncovered = uncovered_policy_files(policy_files, impacted)
    classification = classification(impacted, uncovered)

    reconciliation =
      reconciliation(
        classification,
        impacted,
        changed_subject_ids,
        policy_files,
        changed_files
      )

    lines =
      [
        "Spec Led Next",
        "base=#{base} changed_files=#{length(changed_files)} policy_files=#{length(policy_files)}",
        "classification=#{classification}",
        "reconciliation=#{reconciliation}"
      ] ++
        verbose_lines(Keyword.get(opts, :verbose, false), changed_files, policy_files) ++
        impacted_lines(impacted) ++
        uncovered_lines(uncovered) ++
        ["commands:", "- mix spec.check --base #{base}"]

    %{
      lines: lines,
      base: base,
      changed_files: changed_files,
      policy_files: policy_files,
      classification: classification,
      reconciliation: reconciliation,
      impacted_subjects: impacted
    }
  end

  defp changed_subject_ids(subjects, changed_files) do
    changed = MapSet.new(changed_files)

    subjects
    |> Enum.filter(&MapSet.member?(changed, &1.spec_file))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp impacted_subjects(subjects, policy_files, changed_subject_ids) do
    changed = MapSet.new(policy_files)

    Enum.filter(subjects, fn subject ->
      MapSet.member?(changed_subject_ids, subject.id) or
        Enum.any?(subject.footprint, &MapSet.member?(changed, &1))
    end)
  end

  defp uncovered_policy_files(policy_files, impacted) do
    covered = impacted |> Enum.flat_map(& &1.footprint) |> MapSet.new()

    Enum.reject(policy_files, fn path ->
      PolicyFiles.governance?(path) or PolicyFiles.decision_file?(path) or
        MapSet.member?(covered, path)
    end)
  end

  defp classification(_impacted, [_ | _]), do: "uncovered frontier change"
  defp classification([_], []), do: "covered local change"
  defp classification([_, _ | _], []), do: "covered cross-cutting change"
  defp classification([], []), do: "likely non-contract change"

  defp reconciliation("uncovered frontier change", _impacted, _changed, _policy, _files),
    do: "needs new subject"

  defp reconciliation("likely non-contract change", _impacted, _changed, _policy, _files),
    do: "no contract update needed"

  defp reconciliation(_classification, impacted, changed, policy_files, changed_files) do
    subjects_updated? =
      impacted != [] and Enum.all?(impacted, &MapSet.member?(changed, &1.id))

    decision_needed? = length(policy_files) > 1 and length(impacted) > 1
    decision_changed? = Enum.any?(changed_files, &PolicyFiles.decision_file?/1)

    cond do
      not subjects_updated? -> "needs subject updates"
      decision_needed? and not decision_changed? -> "needs decision update"
      true -> "ready for check"
    end
  end

  defp verbose_lines(false, _changed_files, _policy_files), do: []

  defp verbose_lines(true, changed_files, policy_files) do
    item_lines("changed_files", changed_files) ++ item_lines("policy_files", policy_files)
  end

  defp impacted_lines([]), do: ["impacted_subjects=none"]

  defp impacted_lines(subjects) do
    ["impacted_subjects:"] ++
      Enum.map(subjects, fn subject ->
        files = if subject.footprint == [], do: "none", else: Enum.join(subject.footprint, ",")
        "- #{subject.id} files=#{files}"
      end)
  end

  defp uncovered_lines([]), do: []
  defp uncovered_lines(files), do: item_lines("uncovered_policy_files", files)

  defp item_lines(label, []), do: ["#{label}=none"]
  defp item_lines(label, items), do: ["#{label}:" | Enum.map(items, &"- #{&1}")]
end
