defmodule Ancora.Review.FindingsDelta do
  @moduledoc "Computes repo-state findings on both sides and classifies the change."

  alias Ancora.{Overlap, Verifier}

  @spec repo_findings(map()) :: [Ancora.Finding.t()]
  def repo_findings(index) do
    (index["findings"] || []) ++
      Verifier.verify(index) ++ Overlap.analyze(index["subjects"] || [])
  end

  @spec classify([Ancora.Finding.t()], [Ancora.Finding.t()], [Ancora.Finding.t()]) :: map()
  def classify(base, head, diff_findings \\ [])

  def classify(base, head, diff_findings) when is_list(base) and is_list(head) do
    base_signatures = MapSet.new(base, &signature/1)
    head_signatures = MapSet.new(head, &signature/1)

    {pre_existing, introduced_state} =
      Enum.split_with(head, &MapSet.member?(base_signatures, signature(&1)))

    resolved = Enum.reject(base, &MapSet.member?(head_signatures, signature(&1)))
    introduced = unique(introduced_state ++ diff_findings)

    %{
      introduced: introduced,
      pre_existing: unique(pre_existing),
      resolved: unique(resolved),
      change_verdict: %{
        clean?: introduced == [],
        introduced_count: length(introduced),
        by_severity: Enum.frequencies_by(introduced, & &1.severity)
      }
    }
  end

  defp signature(finding), do: {finding.code, finding.subject, finding.file, finding.message}
  defp unique(findings), do: Enum.uniq_by(findings, &signature/1)
end
