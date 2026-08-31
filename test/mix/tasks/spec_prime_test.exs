Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.PrimeTest do
  use Ancora.TestCase

  alias Ancora.Output

  @moduletag :tmp_dir

  @tag spec: "ancora.tasks.prime_loop"
  @tag spec: "ancora.tasks.report_task_flags"
  test "prime subprocess ends its loop with the check command and read protocol", %{root: root} do
    create_project(root)
    result = run_mix_subprocess(["spec.prime", "--root", root, "--base", "HEAD"])

    assert result.status == 0
    lines = output_lines(result.stdout)
    assert Enum.at(lines, -2) == "* When ready, run mix spec.check --base HEAD."
    assert List.last(lines) == Output.read_protocol()
  end

  @tag spec: "ancora.tasks.report_task_flags"
  test "prime routes usage and environment failures without a verdict", %{root: root} do
    create_project(root)

    usage = run_mix_subprocess(["spec.prime", "--root", root, "--json"])
    assert usage.status == 1
    assert usage.stdout =~ "Invalid arguments for spec.prime: --json"
    refute usage.stdout =~ "result="

    env =
      run_mix_subprocess(["spec.prime", "--root", root, "--base", "missing-report-task-ref"])

    assert env.status == 1
    assert env.stdout =~ "cannot be resolved"
    refute env.stdout =~ "result="
  end

  @tag spec: "ancora.tasks.prime_loop"
  @tag spec: "ancora.tasks.report_task_flags"
  test "prime task callable surface is present" do
    prime = &Mix.Tasks.Spec.Prime.run/1
    assert is_function(prime, 1)
  end

  defp create_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")
  end
end
