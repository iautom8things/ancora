Code.require_file("../../support/ancora_case.exs", __DIR__)
Code.require_file("../../support/retired_vocabulary.ex", __DIR__)

defmodule Ancora.Scaffold.TemplatesTest do
  use Ancora.TestCase, async: false

  setup %{root: root} do
    result = Ancora.Init.scaffold(root)
    {:ok, scaffold: result.directory}
  end

  @tag spec: "ancora.scaffold.agents_md_content"
  test "agent guide carries the working protocol", %{scaffold: scaffold} do
    content = File.read!(Path.join(scaffold, "AGENTS.md"))

    assert content =~ ~r/task's `Advances:`\s+field/
    assert content =~ "Never read the whole corpus"
    assert content =~ Ancora.Output.read_protocol()
    assert content =~ "## There is no generated state"
    assert content =~ "mix spec.prime --base HEAD"
    assert content =~ "derived/unanchored_subject"
  end

  @tag spec: "ancora.scaffold.skill_md_content"
  test "skill triage table contains every registry entry once", %{scaffold: scaffold} do
    content = File.read!(Path.join([scaffold, "agents", "SKILL.md"]))
    [_, table] = Regex.run(~r/## Finding triage\n\n(.*?)\n\nEdit the/s, content)

    for code <- Ancora.Finding.codes() do
      entry = Ancora.Finding.registry()[code]
      assert length(Regex.scan(~r/`#{Regex.escape(code)}`/, table)) == 1
      assert table =~ "| #{entry.family} | `#{code}` | #{entry.default} |"
    end

    assert content =~ "Spec-Ack: <code>=<info|warning>"
    assert content =~ "overrides:"
    assert content =~ "reason:"
  end

  @tag spec: "ancora.scaffold.config_template"
  test "config template loads with the taught defaults", %{root: root, scaffold: scaffold} do
    stderr =
      capture_io(:stderr, fn ->
        send(self(), {:config, Ancora.Config.load(root, known_subjects: ["project.core"])})
      end)

    assert_receive {:config, config}
    content = File.read!(Path.join(scaffold, "config.yml"))

    refute stderr =~ "[CONFIG]"
    assert config.default_base == "origin/main"
    assert config.test_paths == ["test"]
    assert config.lib_paths == nil
    assert config.findings == []
    assert content =~ "# overrides:"
    assert content =~ "#     requirement:"
    assert content =~ "#     reason:"
  end

  @tag spec: "ancora.scaffold.no_retired_vocabulary"
  test "templates and prose contain no retired vocabulary", %{scaffold: scaffold} do
    migration_path = Path.expand("../../../docs/migration.md", __DIR__)
    repo_readme = Path.expand("../../../README.md", __DIR__)
    needles = Ancora.RetiredVocabulary.needles(migration_path)

    assert "branch_guard_dangling_binding" in needles

    documents =
      scaffold
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&{&1, File.read!(&1)})

    documents =
      documents ++
        [
          {repo_readme, File.read!(repo_readme)},
          {migration_path,
           migration_path |> File.read!() |> Ancora.RetiredVocabulary.outside_code_map()}
        ]

    for {path, content} <- documents,
        needle <- needles do
      refute content =~ needle, "#{needle} appears in #{path}"
    end
  end
end
