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
      Overrides in Ancora 1.x are scoped to one subject and one finding code, optionally
      narrowed to one requirement with `requirement:`. The warning clears once config
      supplies the same severity. It remains when config is more severe because removing
      the trailer would still change the gate result.
      """)

    assert promotion_paragraphs(File.read!(@readme)) == expected
    assert promotion_paragraphs(File.read!(@migration)) == expected
  end

  @tag spec: "ancora.scaffold.readme_commitments"
  @tag spec: "ancora.scaffold.migration_doc"
  test "acknowledgment docs teach the requirement-scoped override" do
    assert File.read!(@readme) =~ "requirement:"
    assert File.read!(@migration) =~ "requirement:"
  end

  @tag spec: "ancora.scaffold.migration_doc"
  test "migration map names the complete 33-code registry and its defaults" do
    content = File.read!(@migration)

    [_, code_map] = Regex.run(~r/## Finding code map\n\n(.*?)\n\nThe old trailer/s, content)

    mapped_entries =
      ~r/^\|.*?\| `([^`]+)` \| `(error|warning|info)` \|$/m
      |> Regex.scan(code_map, capture: :all_but_first)

    mapped_codes = Enum.map(mapped_entries, &hd/1)

    assert content =~ "Ancora has 33 finding codes"
    assert MapSet.new(mapped_codes) == MapSet.new(Ancora.Finding.codes())
    assert length(mapped_codes) == map_size(Ancora.Finding.registry())

    for [code, severity] <- mapped_entries do
      assert Atom.to_string(Ancora.Finding.default_severity(code)) == severity
    end

    for step <- 1..9 do
      assert content =~ "#{step}. "
    end

    assert content =~ "## Command gates"
    assert content =~ "vacuity guard"
    assert content =~ "whole-token matching"
  end

  @tag :tmp_dir
  @tag spec: "ancora.scaffold.migration_doc"
  test "source-scan template runs as a copied fixture-project test", %{tmp_dir: root} do
    # Would fail if the documented template or SourceScan stopped compiling or
    # if their public-call shapes drifted apart.
    content = File.read!(@migration)
    [_, template] = Regex.run(~r/```elixir source-scan-test\n(.*?)```/s, content)
    ancora_root = Path.expand("../../..", __DIR__)

    File.mkdir_p!(Path.join(root, "test"))
    File.mkdir_p!(Path.join(root, "lib/ancora"))
    File.mkdir_p!(Path.join(root, "lib/my_app"))
    File.mkdir_p!(Path.join(root, "config"))

    File.cp!(
      Path.join(ancora_root, "lib/ancora/source_scan.ex"),
      Path.join(root, "lib/ancora/source_scan.ex")
    )

    File.write!(Path.join(root, "lib/my_app/example.ex"), "defmodule MyApp.Example, do: nil\n")
    File.write!(Path.join(root, "config/config.exs"), "import Config\n")

    File.write!(Path.join(root, "mix.exs"), """
    defmodule SourceScanFixture.MixProject do
      use Mix.Project

      def project do
        [
          app: :source_scan_fixture,
          version: "0.1.0",
          elixir: "~> 1.18"
        ]
      end
    end
    """)

    File.write!(Path.join(root, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(root, "test/source_policy_test.exs"), template)

    {output, status} =
      System.cmd("mix", ["test"],
        cd: root,
        env: [
          {"MIX_BUILD_PATH", Path.join(root, "_build")},
          {"MIX_QUIET", "1"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "1 test, 0 failures"
  end

  defp promotion_paragraphs(content) do
    content
    |> String.split("\n\n")
    |> Enum.find(&String.starts_with?(&1, "`Spec-Ack:` trailers"))
    |> normalize()
  end

  defp normalize(content), do: content |> String.split() |> Enum.join(" ")
end
