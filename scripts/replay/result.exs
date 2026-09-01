Code.require_file("case.exs", __DIR__)

defmodule AncoraReplay.Result do
  @moduledoc false

  alias AncoraReplay.Case

  @ignored_codes ["derived/unresolved_calls", "format/retired_construct"]
  @failing_severities ["warning", "error"]

  @type evaluation :: {:met, String.t()} | {:failed, String.t()} | {:error, String.t()}

  @spec evaluate(Case.t(), map()) :: evaluation()
  def evaluate(%Case{kind: :drift} = replay_case, report) do
    matches =
      report
      |> findings()
      |> Enum.filter(&(Map.get(&1, "code") == "derived/drift"))
      |> Enum.filter(&names_changed_function?(&1, replay_case.functions))

    if matches == [] do
      observed =
        report
        |> findings()
        |> Enum.map_join(" | ", fn finding ->
          "#{Map.get(finding, "code")}:#{finding_text(finding)}"
        end)

      {:failed,
       "#{replay_case.name}: no derived/drift finding named #{Enum.join(replay_case.functions, ", ")}; " <>
         "observed=#{if(observed == "", do: "none", else: observed)}"}
    else
      {:met, "#{replay_case.name}: drift named #{Enum.join(replay_case.functions, ", ")}"}
    end
  end

  def evaluate(%Case{kind: :control} = replay_case, report) do
    failures = Enum.filter(findings(report), &control_failure?/1)

    if failures == [] do
      {:met, "#{replay_case.name}: control is clean"}
    else
      codes = failures |> Enum.map(&Map.get(&1, "code")) |> Enum.uniq() |> Enum.sort()
      {:failed, "#{replay_case.name}: control emitted #{Enum.join(codes, ", ")}"}
    end
  end

  @spec exit_code([evaluation()]) :: 0 | 1 | 2
  def exit_code(evaluations) when is_list(evaluations) do
    cond do
      Enum.any?(evaluations, &match?({:error, _message}, &1)) -> 2
      Enum.any?(evaluations, &match?({:failed, _message}, &1)) -> 1
      true -> 0
    end
  end

  defp findings(report), do: Map.fetch!(report, "all_findings")

  defp names_changed_function?(finding, functions) do
    text = finding_text(finding)
    Enum.any?(functions, &String.contains?(text, &1))
  end

  defp finding_text(finding) do
    Enum.map_join(["message", "detail"], " ", &to_string(Map.get(finding, &1, "")))
  end

  defp control_failure?(finding) do
    code = Map.get(finding, "code", "")
    severity = Map.get(finding, "severity", "")

    (String.starts_with?(code, "derived/") or String.starts_with?(code, "change/")) and
      code not in @ignored_codes and severity in @failing_severities
  end
end
