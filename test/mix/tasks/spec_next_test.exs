Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.NextTest do
  use Ancora.TestCase

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "next runs as a subprocess with one command and no verdict" do
    result = run_mix_subprocess(["spec.next", "--base", "HEAD", "--verbose"])

    assert result.status == 0
    assert result.stdout =~ "classification="
    assert result.stdout =~ "reconciliation="

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
end
