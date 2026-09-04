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
  test "migration map names the complete 31-code registry" do
    content = File.read!(@migration)

    [_, code_map] = Regex.run(~r/## Finding code map\n\n(.*?)\n\nThe old trailer/s, content)

    mapped_codes =
      ~r/^\|.*?\| `([^`]+)` \|$/m
      |> Regex.scan(code_map, capture: :all_but_first)
      |> List.flatten()

    assert content =~ "Ancora has 31 finding codes"
    assert MapSet.new(mapped_codes) == MapSet.new(Ancora.Finding.codes())
    assert length(mapped_codes) == map_size(Ancora.Finding.registry())

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
end
