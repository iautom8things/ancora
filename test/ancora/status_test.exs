Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.StatusTest do
  use Ancora.TestCase

  alias Ancora.Status

  @tag spec: "ancora.tasks.status_derived_report"
  test "reports empty and thin subjects with fixed threshold", %{root: root} do
    create_project(root)
    write_subject(root, "sample.empty", "sample.empty.works")

    write_files(root, %{
      "lib/thin.ex" => """
      defmodule Thin do
        def work, do: :ok
      end
      """,
      "test/thin_test.exs" => """
      defmodule ThinTest do
        use ExUnit.Case
        @tag spec: "sample.thin.works"
        test "works" do
          assert Thin.work() == :ok
        end
      end
      """,
      ".spec/specs/thin.spec.md" => """
      # Thin

      ```yaml spec-meta
      id: sample.thin
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: sample.thin.works
        statement: The thin sample shall work.
        priority: must
      ```

      ```yaml spec-scenarios
      []
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - sample.thin.works
      ```
      """
    })

    assert {:ok, report} = Status.build(root)
    assert Status.thin_threshold() == 3
    assert "derived subjects=2 empty=1 thin(<3)=2" in report.lines
    assert "sample.empty derived=0 generated=0+0 tests=0 unresolved=0" in report.lines
  end

  @tag spec: "ancora.tasks.status_derived_report"
  test "splits project-macro and dependency-generated bindings", %{root: root} do
    create_project(root)
    write_subject(root, "sample.generated", "sample.generated.works")

    write_files(root, %{
      "lib/project_macro.ex" => """
      defmodule ProjectMacro do
        defmacro __using__(_opts) do
          quote do
            def project_generated, do: :project
          end
        end
      end
      """,
      "lib/sample.ex" => """
      defmodule Sample do
        use ProjectMacro
      end

      defmodule DepSample do
        use ExternalMacro
      end
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.generated.works"
        test "works" do
          assert Sample.project_generated() == :project
          assert DepSample.dep_generated() == :dep
          assert DepSample.other_dep_generated() == :dep
        end
      end
      """,
      ".spec/config.yml" => """
      overrides:
        - subject: sample.generated
          code: derived/unanchored_subject
          severity: info
          reason: integration boundary
      """
    })

    assert {:ok, report} = Status.build(root)
    row = Enum.find(report.subjects, &(&1.id == "sample.generated"))
    assert row.project_generated == 1
    assert row.dep_generated == 2
    assert row.acknowledged?
    assert Enum.any?(report.lines, &(&1 =~ "generated=1+2" and &1 =~ "acknowledged"))
  end

  defp create_project(root) do
    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/.keep" => ""
    })
  end

  defp write_subject(root, id, requirement_id) do
    write_files(root, %{
      ".spec/specs/sample.spec.md" => """
      # Sample

      ```yaml spec-meta
      id: #{id}
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: #{requirement_id}
        statement: The sample shall work.
        priority: must
      ```

      ```yaml spec-scenarios
      []
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - #{requirement_id}
      ```
      """
    })
  end
end
