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

  @tag spec: "ancora.scaffold.readme_commitments"
  @tag spec: "ancora.scaffold.migration_doc"
  test "acknowledgment promotion documents the override scope accepted by 1.x" do
    expected =
      normalize("""
      `Spec-Ack:` trailers are temporary development acknowledgments. Ancora warns when an
      applied trailer exists only below the branch tip because a squash merge will discard
      it. Before merging, copy that severity into `.spec/config.yml` under `severities:` or
      a subject override, add the reason for an override, and commit the config change.
      Overrides in Ancora 1.x are scoped to one subject and one finding code. The warning
      clears once config supplies the same severity. It remains when config is more severe
      because removing the trailer would still change the gate result.
      """)

    assert promotion_paragraphs(File.read!(@readme)) == expected
    assert promotion_paragraphs(File.read!(@migration)) == expected
  end

  @tag spec: "ancora.scaffold.readme_commitments"
  @tag spec: "ancora.scaffold.migration_doc"
  test "acknowledgment docs do not teach unsupported requirement-scoped overrides" do
    refute File.read!(@readme) =~ "requirement:"
    refute File.read!(@migration) =~ "requirement:"
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

  defp promotion_paragraphs(content) do
    content
    |> String.split("\n\n")
    |> Enum.find(&String.starts_with?(&1, "`Spec-Ack:` trailers"))
    |> normalize()
  end

  defp normalize(content), do: content |> String.split() |> Enum.join(" ")
end
