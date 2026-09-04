Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.NextTest do
  use Ancora.TestCase

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "next classifies a fixture's non-contract change with one command and no verdict", %{
    root: root
  } do
    create_fixture(root)
    write_files(root, %{"README.md" => "changed outside the policy files\n"})

    script = """
    File.cd!(#{inspect(root)}, fn ->
      Mix.Tasks.Spec.Next.run(["--base", "HEAD", "--verbose"])
    end)
    """

    result = run_mix_subprocess(["run", "-e", script])

    assert result.status == 0, result.stdout <> result.stderr
    assert result.stdout =~ "classification=uncovered frontier change"
    assert result.stdout =~ "reconciliation=needs new subject"
    assert result.stdout =~ "changed_files:\n- README.md"

    assert Enum.count(output_lines(result.stdout), &String.starts_with?(&1, "- mix spec.check")) ==
             1

    refute result.stdout =~ "result="
  end

  @tag spec: "ancora.tasks.report_task_flags"
  test "next routes usage and environment failures without a verdict" do
    usage = run_mix_subprocess(["spec.next", "--json"])
    assert usage.status == 1
    assert usage.stdout =~ "Invalid arguments for spec.next: --json"
    refute usage.stdout =~ "result="

    env = run_mix_subprocess(["spec.next", "--base", "missing-report-task-ref"])
    assert env.status == 1
    assert env.stdout =~ "cannot be resolved"
    refute env.stdout =~ "result="
  end

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "next task callable surface is present" do
    Code.ensure_loaded!(Mix.Tasks.Spec.Next)
    assert function_exported?(Mix.Tasks.Spec.Next, :run, 1)
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "since takes precedence over base" do
    result =
      run_mix_subprocess([
        "spec.next",
        "--base",
        "missing-report-task-ref",
        "--since",
        "HEAD"
      ])

    assert result.status == 0
    assert result.stdout =~ "base=HEAD"
  end

  defp create_fixture(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture, version: "0.1.0"]
      end
      """,
      ".spec/specs/.keep" => "",
      "README.md" => "base\n"
    })

    commit_all(root, "base")
  end
end
