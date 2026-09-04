defmodule Mix.Tasks.Spec.CliDocsTest do
  use ExUnit.Case, async: true

  @readme Path.expand("../../../README.md", __DIR__)
  @migration Path.expand("../../../docs/migration.md", __DIR__)

  @tag spec: "ancora.scaffold.readme_commitments"
  test "README names the four stable functions and the JSON extraction rule" do
    content = File.read!(@readme)

    for function <- [
          "Ancora.Parser.parse_file/2",
          "Ancora.DecisionParser.parse_file/2",
          "Ancora.check/2",
          "Ancora.validate/2"
        ] do
      assert content =~ function
    end

    assert content =~ "Every other module and function is internal"
    assert content =~ "last stdout line that parses as JSON"
    assert content =~ "The verdict line\nfollows the JSON report"
  end

  @tag spec: "ancora.scaffold.migration_doc"
  test "README and migration guide require an explicit CI base" do
    for content <- [File.read!(@readme), File.read!(@migration)] do
      assert content =~ "CI must"
      assert content =~ "--base"
      assert content =~ "default_base"
      assert content =~ "local-development convenience"
    end
  end
end
