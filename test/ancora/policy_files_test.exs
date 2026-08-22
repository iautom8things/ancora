defmodule Ancora.PolicyFilesTest do
  use ExUnit.Case, async: true

  alias Ancora.PolicyFiles

  describe "governance-file set" do
    @tag spec: "ancora.gate.change_findings"
    test "specs, config.yml, AGENTS.md, and README.md are governance; ADRs are not" do
      assert PolicyFiles.governance?(".spec/specs/ancora.parsing.spec.md")
      assert PolicyFiles.governance?(".spec/config.yml")
      assert PolicyFiles.governance?(".spec/AGENTS.md")
      assert PolicyFiles.governance?(".spec/README.md")
      refute PolicyFiles.governance?(".spec/decisions/ancora.decision.slimmed_governance.md")
      refute PolicyFiles.governance?("lib/ancora.ex")
    end

    @tag spec: "ancora.gate.change_findings"
    test "decision_file? is ADRs under .spec/decisions except README.md" do
      assert PolicyFiles.decision_file?(".spec/decisions/ancora.decision.slimmed_governance.md")
      refute PolicyFiles.decision_file?(".spec/decisions/README.md")
      refute PolicyFiles.decision_file?(".spec/specs/ancora.parsing.spec.md")
    end
  end

  describe "missing_decision?" do
    @tag spec: "ancora.gate.change_findings"
    test "a governance change with no ADR in the same diff is the missing_decision trigger" do
      assert PolicyFiles.missing_decision?([".spec/config.yml"]),
             "Would fail if PolicyFiles.missing_decision? required an extra change_type or treated config.yml as non-governance"

      assert PolicyFiles.missing_decision?([".spec/specs/foo.spec.md", "lib/ancora.ex"])
      refute PolicyFiles.missing_decision?([".spec/config.yml", ".spec/decisions/new.md"])
      refute PolicyFiles.missing_decision?(["lib/ancora.ex"])
      refute PolicyFiles.missing_decision?([".spec/decisions/new.md"])
    end
  end

  describe "classify/1" do
    test "returns a known kind for common paths" do
      paths = [
        "lib/x.ex",
        "test/x_test.exs",
        "docs/x.md",
        "priv/static/app.css",
        "priv/plts/dialyzer.plt",
        "weird/top/level/file.txt",
        "README.md",
        "mix.exs",
        ".spec/config.yml"
      ]

      for path <- paths do
        kind = PolicyFiles.classify(path)
        assert kind in [:lib, :test, :doc, :generated, :unknown], "#{path} -> #{inspect(kind)}"
      end
    end
  end
end
