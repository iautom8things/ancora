defmodule Ancora.Scaffold.DocsTest do
  use ExUnit.Case, async: true

  @readme Path.expand("../../../README.md", __DIR__)
  @migration Path.expand("../../../docs/migration.md", __DIR__)

  @tag spec: "ancora.scaffold.readme_commitments"
  test "README states the public API and operating commitments" do
    content = File.read!(@readme)
    [_, public_api] = Regex.run(~r/## Public API\n\n(.*?)\n\n## /s, content)
    [_, ci] = Regex.run(~r/```yaml\n(.*?)```/s, content)

    assert Regex.scan(~r/`([^`]+)`/, public_api, capture: :all_but_first) == [
             ["Ancora.Parser.parse_file/2"],
             ["Ancora.DecisionParser.parse_file/2"],
             ["--root"]
           ]

    assert content =~ "an internal affordance"
    assert content =~ "This is toolchain introspection,\nnot project execution."
    assert content =~ "mix format --migrate"
    assert length(String.split(ci, "\n", trim: true)) == 6
    refute content =~ ~r/proof/i
    refute content =~ ~r/verified behavior/i
  end

  @tag spec: "ancora.scaffold.migration_doc"
  test "migration map names the complete 30-code registry and its defaults" do
    content = File.read!(@migration)

    [_, code_map] = Regex.run(~r/## Finding code map\n\n(.*?)\n\nThe old trailer/s, content)

    mapped_entries =
      ~r/^\|.*?\| `([^`]+)` \| `(error|warning|info)` \|$/m
      |> Regex.scan(code_map, capture: :all_but_first)

    mapped_codes = Enum.map(mapped_entries, &hd/1)

    assert content =~ "Ancora has 30 finding codes"
    assert MapSet.new(mapped_codes) == MapSet.new(Ancora.Finding.codes())
    assert length(mapped_codes) == map_size(Ancora.Finding.registry())

    for [code, severity] <- mapped_entries do
      assert Atom.to_string(Ancora.Finding.default_severity(code)) == severity
    end

    for step <- 1..8 do
      assert content =~ "#{step}. "
    end
  end
end
