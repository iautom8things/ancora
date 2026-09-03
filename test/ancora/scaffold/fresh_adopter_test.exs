Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Ancora.Scaffold.FreshAdopterTest do
  use Ancora.TestCase

  @tag spec: "ancora.scaffold.fresh_adopter_round_trip"
  test "fresh adopter goes from unanchored red to tagged green", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule FreshAdopter.MixProject do
        use Mix.Project
        def project, do: [app: :fresh_adopter]
      end
      """
    })

    commit_all(root, "empty project")

    init = run_mix_subprocess(["spec.init", "--root", root])
    assert init.status == 0
    assert init.stdout =~ "spec.init scaffolded"

    red = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    assert red.status == 1
    assert red.stdout =~ "derived/unanchored_subject"
    assert List.last(lines(red.stdout)) =~ "spec.check result=fail tier=branch"

    write_files(root, %{
      "lib/project_core.ex" => """
      defmodule ProjectCore do
        def run, do: :ok
      end
      """,
      "test/project_core_test.exs" => """
      defmodule ProjectCoreTest do
        use ExUnit.Case

        @tag spec: "project.core.works"
        test "runs" do
          assert ProjectCore.run() == :ok
        end
      end
      """
    })

    commit_all(root, "anchor project core")

    green = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    assert green.status == 0, green.stdout <> green.stderr
    assert List.last(lines(green.stdout)) == "spec.check result=pass"
  end

  defp lines(output), do: String.split(output, "\n", trim: true)
end
