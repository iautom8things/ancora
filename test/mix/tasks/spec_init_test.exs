Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.InitTest do
  use Ancora.TestCase

  @tag spec: "ancora.scaffold.init_writes_templates"
  test "writes the complete scaffold and reports every file", %{root: root} do
    stdout = capture_io(fn -> Mix.Tasks.Spec.Init.run(["--root", root]) end)

    expected = [
      "AGENTS.md",
      "agents/SKILL.md",
      "README.md",
      "config.yml",
      "decisions/README.md",
      "specs/project.core.spec.md"
    ]

    for relative <- expected do
      path = Path.join([root, ".spec", relative])
      assert File.regular?(path)
      assert stdout =~ "wrote #{path}"
    end

    assert String.split(stdout, "\n", trim: true) |> List.last() ==
             "spec.init scaffolded #{Path.join(root, ".spec")}"

    refute File.exists?(Path.join(root, ".github"))
  end

  @tag spec: "ancora.scaffold.init_writes_templates"
  test "keeps an edited file unless force is set", %{root: root} do
    capture_io(fn -> Mix.Tasks.Spec.Init.run(["--root", root]) end)
    agents_path = Path.join([root, ".spec", "AGENTS.md"])
    File.write!(agents_path, "hand edited\n")

    kept = capture_io(fn -> Mix.Tasks.Spec.Init.run(["--root", root]) end)
    assert kept =~ "kept #{agents_path}"
    assert File.read!(agents_path) == "hand edited\n"

    wrote = capture_io(fn -> Mix.Tasks.Spec.Init.run(["--root", root, "--force"]) end)
    assert wrote =~ "wrote #{agents_path}"
    assert File.read!(agents_path) =~ "# Ancora agent guide"
  end

  @tag spec: "ancora.tasks.gated_emission_paths"
  test "routes invalid arguments through the gated report path" do
    output =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/Invalid arguments for spec.init/, fn ->
          Mix.Tasks.Spec.Init.run(["--json"])
        end
      end)

    assert output == "Invalid arguments for spec.init: --json\n"
    refute output =~ "result="
  end
end
