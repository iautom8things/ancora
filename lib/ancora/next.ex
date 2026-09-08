defmodule Ancora.Next do
  @moduledoc """
  Classifies the current change set and reports the next spec-led action.

  Classification and reconciliation labels are kept byte-for-byte compatible
  with specled_ex because agent workflows consume them as an API.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.ChangeAnalysis
  alias Ancora.Derive.RunContext
  alias Ancora.Gate.Preflight
  alias Ancora.PolicyFiles
  alias Ancora.Status

  @spec build(Path.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def build(root, opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)
    {status, opts} = Keyword.pop(opts, :status)
    base = Keyword.get(opts, :since) || Keyword.get(opts, :base)

    with {:ok, preflight} <- Preflight.run(root, Keyword.put(opts, :base, base)),
         {:ok, change_set} <- change_set(preflight.root, preflight.base),
         {:ok, status} <- status(root, opts, status) do
      {:ok, report(preflight, change_set, status, opts)}
    end
  end

  defp status(root, opts, nil), do: Status.build(root, opts)
  defp status(_root, _opts, %{subjects: _subjects} = status), do: {:ok, status}

  defp change_set(root, base) do
    with {:ok, context} <- RunContext.start(root, base) do
      try do
        ChangeSet.compute(context)
      after
        RunContext.stop(context)
      end
    end
  end

  defp report(preflight, change_set, status, opts) do
    base = preflight.base
    subjects = status.subjects
    lib_paths = preflight.project.lib_paths
    changed_files = ChangeSet.paths(change_set)

    policy_files =
      Enum.filter(changed_files, fn path ->
        PolicyFiles.policy_target?(path) or ChangeAnalysis.under_lib_path?(path, lib_paths) or
          PolicyFiles.governance?(path, preflight.spec_dir) or
          PolicyFiles.decision_file?(path, preflight.spec_dir)
      end)

    changed_subject_ids = changed_subject_ids(subjects, changed_files)
    impacted = impacted_subjects(subjects, changed_files, changed_subject_ids)
    uncovered = uncovered_source_files(changed_files, subjects, lib_paths)
    classification = classification(impacted, uncovered)
    index = Map.get(status, :index, %{"subjects" => [], "decisions" => []})
    decision_needed? = ChangeAnalysis.missing_decision_findings(changed_files, index) != []

    reconciliation =
      reconciliation(
        classification,
        impacted,
        changed_subject_ids,
        Enum.filter(changed_files, &ChangeAnalysis.under_lib_path?(&1, lib_paths)),
        decision_needed?
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
        ["commands:", "- #{check_command(base, opts)}"]

    %{
      lines: lines,
      base: base,
      changed_files: changed_files,
      policy_files: policy_files,
      classification: classification,
      reconciliation: reconciliation,
      impacted_subjects: impacted,
      command: check_command(base, opts)
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

  defp uncovered_source_files(changed_files, subjects, lib_paths) do
    covered = subjects |> Enum.flat_map(& &1.footprint) |> MapSet.new()

    changed_files
    |> Enum.filter(&ChangeAnalysis.under_lib_path?(&1, lib_paths))
    |> Enum.reject(&MapSet.member?(covered, &1))
  end

  defp classification(_impacted, [_ | _]), do: "uncovered frontier change"
  defp classification([_], []), do: "covered local change"
  defp classification([_, _ | _], []), do: "covered cross-cutting change"
  defp classification([], []), do: "likely non-contract change"

  defp reconciliation("uncovered frontier change", _impacted, _changed, _policy, _files),
    do: "needs new subject"

  defp reconciliation(_classification, _impacted, _changed, _source_files, true),
    do: "needs decision update"

  defp reconciliation("likely non-contract change", _impacted, _changed, _policy, false),
    do: "no contract update needed"

  defp reconciliation(_classification, impacted, changed, source_files, false) do
    needs_update? =
      Enum.any?(impacted, fn subject ->
        not MapSet.member?(changed, subject.id) and
          Enum.any?(subject.footprint, &(&1 in source_files))
      end)

    if needs_update?, do: "needs subject updates", else: "ready for check"
  end

  @doc false
  def check_command(base, opts) do
    args = ["mix", "spec.check", "--base", shell_argument(base)]
    workspace_command(args, opts)
  end

  @doc false
  def next_command(opts), do: workspace_command(["mix", "spec.next"], opts)

  defp workspace_command(args, opts) do
    args =
      if opts[:spec_dir], do: args ++ ["--spec-dir", shell_argument(opts[:spec_dir])], else: args

    Enum.join(args, " ")
  end

  defp shell_argument(value) do
    if Regex.match?(~r/\A[a-zA-Z0-9_\.\/@:+-]+\z/, value),
      do: value,
      else: "'" <> String.replace(value, "'", "'\\''") <> "'"
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
