Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.StatusTest do
  use Ancora.TestCase

  @moduletag :tmp_dir

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
