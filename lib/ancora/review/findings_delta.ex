defmodule Ancora.Review.FindingsDelta do
  @moduledoc "Computes repo-state findings on both sides and classifies the change."

  alias Ancora.{Overlap, Verifier}

  @spec repo_findings(map()) :: [Ancora.Finding.t()]
  def repo_findings(index) do
    (index["findings"] || []) ++
      Verifier.verify(index) ++ Overlap.analyze(index["subjects"] || [])
  end

  @spec classify([Ancora.Finding.t()], [Ancora.Finding.t()], [Ancora.Finding.t()]) :: map()
  def classify(base, head, diff_findings \\ [], opts \\ [])

  def classify(base, head, diff_findings, opts) when is_list(base) and is_list(head) do
    base_presence = Keyword.get(opts, :base_presence, base)
    head_presence = Keyword.get(opts, :head_presence, head)
    base_signatures = MapSet.new(base_presence, &signature/1)
    head_signatures = MapSet.new(head_presence, &signature/1)
    base_by_id = Map.new(base, &{signature(&1), &1})
    head_by_id = Map.new(head, &{signature(&1), &1})

    policy_changes =
      head_presence
      |> Enum.filter(&MapSet.member?(base_signatures, signature(&1)))
      |> Enum.flat_map(fn finding ->
        key = signature(finding)
        before = Map.get(base_by_id, key)
        after_finding = Map.get(head_by_id, key)
        old = if before, do: {before.severity, before.severity_source}, else: {:off, :config}

        new =
          if after_finding,
            do: {after_finding.severity, after_finding.severity_source},
            else: {:off, :config}

        if old == new, do: [], else: [%{finding: finding, before: old, after: new}]
      end)

    {pre_existing, introduced_state} =
      Enum.split_with(head, &MapSet.member?(base_signatures, signature(&1)))

    resolved = Enum.reject(base, &MapSet.member?(head_signatures, signature(&1)))
    introduced = unique(introduced_state ++ diff_findings)

    %{
      introduced: introduced,
      policy_changes: policy_changes,
      pre_existing: unique(pre_existing),
      resolved: unique(resolved),
      change_verdict: %{
        clean?: not Enum.any?(introduced, &Ancora.Severity.blocking?(&1.severity)),
        introduced_count: length(introduced),
        by_severity: Enum.frequencies_by(introduced, & &1.severity)
      }
    }
  end

  defp signature(finding),
    do: {finding.code, finding.subject, finding.requirement, finding.file, finding.message}

  defp unique(findings), do: Enum.uniq_by(findings, &signature/1)
end
