Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.WorkspaceTest do
  use Ancora.TestCase

  setup %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" =>
        "defmodule Sample.MixProject do\n use Mix.Project\n def project, do: [app: :sample]\nend\n",
      "contracts folder/config.yml" =>
        "default_base: HEAD\nlib_paths: [src]\ntest_paths: [checks]\n",
      "contracts folder/specs/sample.spec.md" => """
      # Sample
      ```yaml spec-meta
      id: sample.core
      kind: module
      status: active
      ```
      ```yaml spec-requirements
      - id: sample.core.value
        statement: The sample shall return its current value.
        priority: must
      ```
      ```yaml spec-verification
      - kind: tagged_tests
        covers: [sample.core.value]
      ```
      """,
      "src/sample.ex" => "defmodule Sample, do: def(value, do: :base)\n",
      "checks/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.core.value"
        test "value", do: assert(Sample.value() == :base)
      end
      """
    })

    commit_all(root, "custom workspace")
    :ok
  end

  @tag spec: ["ancora.tasks.check_flags", "ancora.gate.preflight_hard_fails"]
  test "check rejects empty and outside-project workspaces with actionable errors", %{root: root} do
    assert {:env, empty} = Ancora.check(root, base: "HEAD", spec_dir: "")
    assert empty =~ "--spec-dir must not be empty"
    assert {:env, outside} = Ancora.check(root, base: "HEAD", spec_dir: Path.dirname(root))
    assert outside =~ "workspace inside"
    assert outside =~ "compared with git"
  end

  @tag spec: ["ancora.tasks.check_flags", "ancora.gate.preflight_hard_fails"]
  test "check uses the selected workspace config and compares committed bytes", %{root: root} do
    for spec_dir <- [
          "contracts folder",
          "./contracts folder/",
          Path.join(root, "contracts folder")
        ] do
      assert {:ok, clean} = Ancora.check(root, spec_dir: spec_dir)
      refute clean.fail
      assert clean.checked.subjects == 1
      assert clean.checked.requirements == 1

      write_files(root, %{"src/sample.ex" => "defmodule Sample, do: def(value, do: :changed)\n"})
      assert {:ok, changed} = Ancora.check(root, spec_dir: spec_dir)
      assert changed.fail

      assert Enum.any?(
               changed.all_findings,
               &(&1.code == "derived/drift" and &1.file == "src/sample.ex")
             )

      refute Enum.any?(changed.all_findings, &(&1.code == "derived/unanchored_subject"))
      write_files(root, %{"src/sample.ex" => "defmodule Sample, do: def(value, do: :base)\n"})
    end
  end

  @tag spec: [
         "ancora.tasks.validate_flags",
         "ancora.tasks.report_task_flags",
         "ancora.tasks.prime_loop"
       ]
  test "validation, status, and prime use the same workspace and configuration", %{root: root} do
    opts = [spec_dir: "contracts folder"]
    assert {:ok, validation} = Ancora.validate(root, Keyword.put(opts, :strict, true))
    refute validation.fail
    assert validation.checked.requirements == 1
    assert {:ok, status} = Ancora.Status.build(root, opts)
    assert [%{id: "sample.core", derived: 1, tests: 1}] = status.subjects
    assert {:ok, prime} = Ancora.Prime.build(root, opts)
    assert Enum.any?(prime.lines, &String.contains?(&1, "--spec-dir 'contracts folder'"))
  end

  @tag spec: ["ancora.gate.change_findings", "ancora.tasks.next_labels_verbatim"]
  test "a workspace at the project root uses root governance paths", %{root: root} do
    File.rename!(Path.join(root, "contracts folder/specs"), Path.join(root, "specs"))
    File.rename!(Path.join(root, "contracts folder/config.yml"), Path.join(root, "config.yml"))
    commit_all(root, "workspace at root")
    write_files(root, %{"README.md" => "Workspace guidance\n"})
    assert {:ok, check} = Ancora.check(root, spec_dir: ".")

    assert Enum.any?(
             check.all_findings,
             &(&1.code == "change/missing_decision" and &1.file == "README.md")
           )

    assert {:ok, next} = Ancora.Next.build(root, spec_dir: ".")
    assert next.reconciliation == "needs decision update"
  end

  @tag spec: ["ancora.gate.change_findings", "ancora.tasks.next_labels_verbatim"]
  test "the selected workspace supplies governance paths and clearing decisions", %{root: root} do
    opts = [spec_dir: "./contracts folder/"]
    write_files(root, %{"contracts folder/README.md" => "Corpus guidance\n"})
    assert {:ok, check} = Ancora.check(root, opts)

    assert Enum.any?(
             check.all_findings,
             &(&1.code == "change/missing_decision" and &1.file == "contracts folder/README.md")
           )

    assert {:ok, next} = Ancora.Next.build(root, opts)
    assert next.reconciliation == "needs decision update"

    write_files(root, %{
      "contracts folder/decisions/guidance.md" => """
      ---
      id: sample.decision.guidance
      status: accepted
      date: 2026-09-07
      affects: [sample.core]
      ---
      # Guidance
      ## Context
      Contributors need corpus guidance.
      ## Decision
      Keep the contributor workflow in the workspace README.
      ## Consequences
      Contributors can find the workflow beside the specs.
      """
    })

    assert {:ok, cleared} = Ancora.check(root, opts)
    refute cleared.fail
    assert {:ok, next} = Ancora.Next.build(root, opts)
    assert next.reconciliation == "no contract update needed"
  end

  @tag spec: "ancora.review.view_model_builder"
  test "review compares the selected workspace at the base and working tree", %{root: root} do
    write_files(root, %{"src/sample.ex" => "defmodule Sample, do: def(value, do: :changed)\n"})
    assert {:ok, view} = Ancora.Review.build(root, spec_dir: Path.join(root, "contracts folder"))
    assert [subject] = view.subjects

    assert [%{binding: "Sample.value/0", badge: :drift, lines: lines}] =
             subject.code.watched_interface

    assert Enum.any?(lines, fn {kind, text} -> kind == :add and text =~ ":changed" end)
  end
end
