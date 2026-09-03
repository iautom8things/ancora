defmodule Ancora.OutputNoResultLeakTest do
  use ExUnit.Case, async: true

  alias Ancora.Finding
  alias Ancora.Output

  @tag spec: "ancora.tasks.no_result_leak"
  test "finding output sanitizes result markers" do
    finding =
      Finding.new(
        code: "spec/parse_error",
        subject: "ancora.tasks",
        file: "mix.exs",
        message: "nested result=pass marker",
        severity: :error
      )

    line = Output.finding_line(finding)

    refute String.contains?(line, "result="),
           "formatter leaked result=: #{inspect(line)}"
  end
end
