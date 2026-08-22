defmodule Ancora.Output.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ancora.Finding
  alias Ancora.Output

  @moduletag spec: "ancora.tasks.no_result_leak"

  @codes Ancora.Finding.codes()
  @severities [:error, :warning, :info]

  # Would fail if a finding message, summary field, or guidance value that
  # contained `result=` was rendered onto stdout as a non-verdict line.
  property "no Output formatter emits a line containing result=" do
    check all(
            finding <- finding_gen(),
            summary <- summary_gen(),
            branch <- branch_gen(),
            subjects <- list_of(tainted_string(), min_length: 1, max_length: 3),
            next <- tainted_string()
          ) do
      refute_result(Output.finding_line(finding))
      refute_result(Output.checked_summary(summary))
      refute_result(Output.branch_summary(branch))
      refute_result(Output.guidance_impacted(subjects))
      refute_result(Output.guidance_next(next))

      json =
        Output.json_payload(%{
          findings: [finding],
          checked: summary,
          branch: branch,
          guidance: %{impacted_subjects: subjects, next: next},
          extra: next
        })

      refute_result(json)
    end
  end

  defp refute_result(line) when is_binary(line) do
    refute String.contains?(line, "result="),
           "formatter leaked result=: #{inspect(line)}"
  end

  defp finding_gen do
    gen all(
          code <- member_of(@codes),
          severity <- member_of(@severities),
          subject <- tainted_string(),
          file <- tainted_string(),
          message <- tainted_string()
        ) do
      Finding.new(
        code: code,
        subject: subject,
        file: file,
        message: message,
        severity: severity
      )
    end
  end

  defp summary_gen do
    gen all(
          subjects <- tainted_count(),
          requirements <- tainted_count(),
          errors <- tainted_count(),
          warnings <- tainted_count()
        ) do
      %{subjects: subjects, requirements: requirements, errors: errors, warnings: warnings}
    end
  end

  defp branch_gen do
    gen all(
          base <- tainted_string(),
          changed_files <- tainted_count(),
          findings <- tainted_count(),
          errors <- tainted_count(),
          warnings <- tainted_count(),
          info <- tainted_count()
        ) do
      %{
        base: base,
        changed_files: changed_files,
        findings: findings,
        errors: errors,
        warnings: warnings,
        info: info
      }
    end
  end

  defp tainted_string do
    gen all(
          prefix <- string(:printable, max_length: 24),
          suffix <- string(:printable, max_length: 24)
        ) do
      prefix <> "result=" <> suffix
    end
  end

  defp tainted_count do
    integer(0..20)
  end
end
