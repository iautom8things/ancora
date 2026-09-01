defmodule AncoraReplay.Json do
  @moduledoc false

  @verdict_prefix "spec.check result="

  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(stdout) when is_binary(stdout) do
    lines = String.split(stdout, "\n", trim: true)

    with :ok <- validate_verdict(lines),
         {:ok, report} <- decode_report(Enum.drop(lines, -1)),
         :ok <- validate_report(report) do
      {:ok, report}
    end
  end

  defp validate_verdict([]), do: {:error, "spec.check produced no stdout"}

  defp validate_verdict(lines) do
    if lines |> List.last() |> String.starts_with?(@verdict_prefix) do
      :ok
    else
      {:error, "spec.check verdict is missing or is not the last stdout line"}
    end
  end

  defp decode_report(lines) do
    reports =
      Enum.flat_map(lines, fn line ->
        case Jason.decode(line) do
          {:ok, report} when is_map(report) -> [report]
          _other -> []
        end
      end)

    case reports do
      [report] -> {:ok, report}
      [] -> {:error, "spec.check stdout has no JSON report"}
      _many -> {:error, "spec.check stdout has more than one JSON report"}
    end
  end

  defp validate_report(%{"all_findings" => findings}) when is_list(findings), do: :ok
  defp validate_report(_report), do: {:error, "spec.check JSON report has no all_findings list"}
end
