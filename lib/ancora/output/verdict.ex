defmodule Ancora.Output.Verdict do
  @moduledoc """
  The only producer of the `result=` string.

  Grammar:

      spec.check result=pass
      spec.check result=fail tier=<usage|env|validate|branch> errors=<E> warnings=<W>
      spec.validate result=pass
      spec.validate result=fail tier=<usage|env|validate> errors=<E> warnings=<W>
  """

  alias Ancora.Finding

  @gate_tasks ["spec.check", "spec.validate"]
  @check_tiers [:usage, :env, :validate, :branch]
  @validate_tiers [:usage, :env, :validate]

  @doc """
  Write the verdict line for `task_name` given a report map.

  Pass is `spec.<task> result=pass`. Fail includes `tier=` and counts.
  """
  @spec emit(String.t(), map()) :: String.t()
  def emit(task_name, report)
      when task_name in @gate_tasks and is_map(report) do
    {errors, warnings} = counts(report)

    line =
      if pass?(report) do
        "#{task_name} result=pass"
      else
        tier = tier(task_name, report)
        "#{task_name} result=fail tier=#{tier} errors=#{errors} warnings=#{warnings}"
      end

    IO.puts(line)
    line
  end

  @doc "Emit a fail verdict with zero findings for a hard-fail path."
  @spec emit_fail(String.t(), atom()) :: String.t()
  def emit_fail(task_name, tier) when task_name in @gate_tasks do
    emit(task_name, %{fail: true, tier: tier, errors: 0, warnings: 0})
  end

  @doc false
  @spec counts(map()) :: {non_neg_integer(), non_neg_integer()}
  def counts(report) when is_map(report) do
    errors = explicit_count(report, :errors) || severity_count(report, :error)
    warnings = explicit_count(report, :warnings) || severity_count(report, :warning)
    {errors, warnings}
  end

  @doc false
  @spec pass?(map()) :: boolean()
  def pass?(report) when is_map(report) do
    {errors, warnings} = counts(report)

    cond do
      Map.get(report, :fail) == true -> false
      Map.get(report, :pass) == true -> true
      true -> errors == 0 and warnings == 0
    end
  end

  defp tier("spec.check", report) do
    case normalize_tier(report[:tier] || report["tier"]) do
      tier when tier in @check_tiers -> tier
      _ -> :branch
    end
  end

  defp tier("spec.validate", report) do
    case normalize_tier(report[:tier] || report["tier"]) do
      :branch -> :validate
      tier when tier in @validate_tiers -> tier
      _ -> :validate
    end
  end

  defp normalize_tier(tier) when tier in @check_tiers, do: tier
  defp normalize_tier("usage"), do: :usage
  defp normalize_tier("env"), do: :env
  defp normalize_tier("validate"), do: :validate
  defp normalize_tier("branch"), do: :branch
  defp normalize_tier(_), do: nil

  defp explicit_count(report, key) do
    case Map.get(report, key) || Map.get(report, Atom.to_string(key)) do
      n when is_integer(n) and n >= 0 -> n
      _ -> nil
    end
  end

  defp severity_count(report, severity) do
    report
    |> Map.get(:findings, [])
    |> Enum.count(fn
      %Finding{severity: ^severity} -> true
      _ -> false
    end)
  end
end
