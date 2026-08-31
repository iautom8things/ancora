Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.ValidateTest do
  use Ancora.TestCase

  @tag spec: "ancora.tasks.validate_flags"
  test "rejects output and emits one usage verdict", %{root: root} do
    create_corpus(root)
    result = System.cmd("mix", ["spec.validate", "--root", root, "--output", "x.json"])

    assert {stdout, 1} = result

    assert List.last(String.split(stdout, "\n", trim: true)) =~
             "spec.validate result=fail tier=usage"
  end

  @tag spec: "ancora.tasks.finding_line_format"
  test "prints checked summary without the retired validate status line", %{root: root} do
    create_corpus(root)
    {stdout, 0} = System.cmd("mix", ["spec.validate", "--root", root])

    assert stdout =~ "checked subjects=0 requirements=0 errors=0 warnings=0"
    refute stdout =~ "validate status="

    assert List.last(String.split(stdout, "\n", trim: true)) ==
             "spec.validate result=pass"
  end

  @tag spec: "ancora.gate.strict_verdict"
  @tag spec: "ancora.tasks.exit_codes"
  test "warnings pass validate unless strict is requested", %{root: root} do
    create_corpus(root)
    write_config(root, "test_tags: []\n")

    {normal, 0} = System.cmd("mix", ["spec.validate", "--root", root])
    assert List.last(String.split(normal, "\n", trim: true)) == "spec.validate result=pass"

    {strict, 1} = System.cmd("mix", ["spec.validate", "--root", root, "--strict"])

    assert List.last(String.split(strict, "\n", trim: true)) =~
             "spec.validate result=fail tier=validate"
  end

  defp create_corpus(root) do
    write_files(root, %{".spec/specs/.keep" => ""})
  end
end
