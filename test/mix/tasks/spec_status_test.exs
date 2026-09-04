Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.StatusTest do
  use Ancora.TestCase

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.status_derived_report"
  test "status exits zero for an unanchored corpus and reports the derived set", %{root: root} do
    create_project(root)
    result = run_mix_subprocess(["spec.status", "--root", root])

    assert result.status == 0
    assert result.stdout =~ "derived subjects=1 empty=1 thin(<3)=1"
    refute result.stdout =~ "result="
  end

  @tag spec: "ancora.tasks.report_task_flags"
  test "status rejects json without a verdict", %{root: root} do
    create_project(root)
    result = run_mix_subprocess(["spec.status", "--root", root, "--json"])

    assert result.status == 1
    assert result.stdout =~ "Invalid arguments for spec.status: --json"
    refute result.stdout =~ "result="
  end

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.status_derived_report"
  test "status routes an environment failure without a verdict", %{root: root} do
    create_project(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: app_name()]
        defp app_name, do: :fixture
      end
      """
    })

    result = run_mix_subprocess(["spec.status", "--root", root])
    assert result.status == 1
    assert result.stdout =~ "must define app: as a literal atom"
    refute result.stdout =~ "result="
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  @tag spec: "ancora.tasks.status_derived_report"
  test "status reports a missing corpus without changing its exit contract", %{root: root} do
    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """
    })

    result = run_mix_subprocess(["spec.status", "--root", root])
    assert result.status == 1
    assert result.stdout =~ "no .spec/ directory"
    assert result.stdout =~ "mix spec.init"
    refute result.stdout =~ "result="
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  @tag spec: "ancora.tasks.gated_emission_paths"
  test "status routes an invalid workspace without a stack trace", %{root: root} do
    create_project(root)

    status = run_mix_subprocess(["spec.status", "--root", root, "--spec-dir", "nope"])
    assert status.status == 1
    assert status.stdout =~ "--spec-dir selects the ancora workspace directory"
    assert status.stdout =~ "nope/specs directory not found"
    refute status.stdout =~ "result="
    refute status.stderr =~ "** (RuntimeError)"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  @tag spec: "ancora.tasks.gated_emission_paths"
  test "validate routes an invalid workspace without a stack trace", %{root: root} do
    create_project(root)

    validate = run_mix_subprocess(["spec.validate", "--root", root, "--spec-dir", "nope"])
    assert validate.status == 1
    assert validate.stdout =~ "--spec-dir selects the ancora workspace directory"
    assert validate.stdout =~ "nope/specs directory not found"

    assert List.last(output_lines(validate.stdout)) ==
             "spec.validate result=fail tier=env errors=0 warnings=0"

    refute validate.stderr =~ "** (RuntimeError)"
  end

  @tag spec: "ancora.review.meta_line_shape"
  test "review routes an invalid workspace without a stack trace", %{root: root} do
    create_project(root)

    review = run_mix_subprocess(["spec.review", "--root", root, "--spec-dir", "nope"])
    assert review.status == 1
    assert review.stdout =~ "nope/specs directory not found"
    refute review.stdout =~ "result="
    refute review.stderr =~ "** (RuntimeError)"
  end

  @tag spec: "ancora.tasks.report_task_flags"
  test "status task callable surface is present" do
    Code.ensure_loaded!(Mix.Tasks.Spec.Status)
    assert function_exported?(Mix.Tasks.Spec.Status, :run, 1)
  end

  defp create_project(root) do
    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/sample.spec.md" => """
      # Sample

      ```yaml spec-meta
      id: sample.subject
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: sample.subject.works
        statement: The sample shall work.
        priority: must
      ```

      ```yaml spec-scenarios
      []
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - sample.subject.works
      ```
      """
    })
  end
end
