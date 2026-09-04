defmodule Ancora.Output.VerdictTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Ancora.Finding
  alias Ancora.Output
  alias Ancora.Output.Verdict

  @moduletag spec: "ancora.tasks.verdict_grammar"

  defp finding(code, severity) do
    Finding.new(
      code: code,
      subject: "ancora.tasks",
      file: "lib/ancora/output.ex",
      severity: severity
    )
  end

  test "spec.check pass is exactly spec.check result=pass" do
    stdout =
      capture_io(fn ->
        assert "spec.check result=pass" = Verdict.emit("spec.check", %{findings: []})
      end)

    assert String.trim(stdout) == "spec.check result=pass"
  end

  test "spec.validate pass is exactly spec.validate result=pass" do
    stdout =
      capture_io(fn ->
        assert "spec.validate result=pass" = Verdict.emit("spec.validate", %{})
      end)

    assert String.trim(stdout) == "spec.validate result=pass"
  end

  test "pass predicate honors explicit outcomes before finding counts" do
    # Would fail if Verdict changed the explicit-outcome precedence or ignored finding counts.
    error = finding("derived/drift", :error)

    refute Verdict.pass?(%{fail: true})
    refute Verdict.pass?(%{fail: true, pass: true})
    assert Verdict.pass?(%{pass: true, findings: [error]})
    assert Verdict.pass?(%{findings: []})
    refute Verdict.pass?(%{findings: [error]})
  end

  test "gated output delegates to the verdict pass predicate" do
    # Would fail if Output used finding counts instead of Verdict.pass?/1 for its exit decision.
    error = finding("derived/drift", :error)

    stdout =
      capture_io(fn ->
        assert :ok = Output.gated("spec.check", fn -> {:ok, %{pass: true, findings: [error]}} end)
      end)

    assert stdout |> String.split("\n", trim: true) |> List.last() == "spec.check result=pass"

    source = File.read!(Path.expand("lib/ancora/output.ex"))

    assert source =~ "Verdict.pass?(report)"
    refute source =~ "defp passed?"
  end

  test "spec.check fail includes tier and counts" do
    report = %{
      fail: true,
      tier: :branch,
      findings: [finding("derived/drift", :error)]
    }

    stdout =
      capture_io(fn ->
        assert "spec.check result=fail tier=branch errors=1 warnings=0" =
                 Verdict.emit("spec.check", report)
      end)

    assert String.trim(stdout) ==
             "spec.check result=fail tier=branch errors=1 warnings=0"
  end

  test "spec.validate fail grammar has no branch tier" do
    report = %{
      fail: true,
      tier: :validate,
      findings: [finding("spec/parse_error", :error), finding("derived/growth", :warning)]
    }

    stdout =
      capture_io(fn ->
        assert "spec.validate result=fail tier=validate errors=1 warnings=1" =
                 Verdict.emit("spec.validate", report)
      end)

    assert String.trim(stdout) ==
             "spec.validate result=fail tier=validate errors=1 warnings=1"
  end

  test "emit_fail writes usage and env with zero counts" do
    usage =
      capture_io(fn ->
        assert "spec.check result=fail tier=usage errors=0 warnings=0" =
                 Verdict.emit_fail("spec.check", :usage)
      end)

    env =
      capture_io(fn ->
        assert "spec.validate result=fail tier=env errors=0 warnings=0" =
                 Verdict.emit_fail("spec.validate", :env)
      end)

    assert String.trim(usage) == "spec.check result=fail tier=usage errors=0 warnings=0"
    assert String.trim(env) == "spec.validate result=fail tier=env errors=0 warnings=0"
  end

  test "spec.validate clamps a branch tier to validate" do
    stdout =
      capture_io(fn ->
        Verdict.emit("spec.validate", %{fail: true, tier: :branch})
      end)

    assert String.trim(stdout) ==
             "spec.validate result=fail tier=validate errors=0 warnings=0"
  end
end
