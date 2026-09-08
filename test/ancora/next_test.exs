Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.NextTest do
  use Ancora.TestCase

  alias Ancora.Next

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "suggested commands preserve literal workspace arguments through the shell" do
    for workspace <- ["~root", "contracts{1..3}", "contracts' archive"] do
      check = Next.check_command("HEAD", spec_dir: workspace)
      next = Next.next_command(spec_dir: workspace)

      for {command, expected} <- [
            {check, ["spec.check", "--base", "HEAD", "--spec-dir", workspace]},
            {next, ["spec.next", "--spec-dir", workspace]}
          ] do
        script = "mix() { printf '%s\\n' \"$@\"; }; " <> command
        assert {output, 0} = System.cmd("bash", ["-c", script])
        assert String.split(output, "\n", trim: true) == expected
      end
    end
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "prints covered local change and needs subject updates verbatim", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")
    write_files(root, %{"lib/sample.ex" => sample_module(":changed")})

    assert {:ok, report} = Next.build(root, base: "HEAD")
    assert report.classification == "covered local change"
    assert report.reconciliation == "needs subject updates"
    assert Enum.count(report.lines, &String.starts_with?(&1, "- mix spec.check")) == 1
    assert Enum.any?(report.lines, &(&1 =~ "sample.subject files="))
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "uses a status report supplied by a composing task", %{root: root} do
    # Would fail if Next ignored the status already built by Prime and derived it again.
    create_anchored_project(root)
    commit_all(root, "base")
    write_files(root, %{"lib/sample.ex" => sample_module(":changed")})

    status = %{subjects: []}

    assert {:ok, report} = Next.build(root, base: "HEAD", status: status)
    assert report.classification == "uncovered frontier change"
    assert report.reconciliation == "needs new subject"
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "a subject update still needs its missing governance decision", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => sample_module(":changed"),
      ".spec/specs/sample.spec.md" => subject_spec("The sample shall return the changed value.")
    })

    assert {:ok, report} = Next.build(root, base: "HEAD")
    assert report.classification == "covered local change"
    assert report.reconciliation == "needs decision update"
    assert {:ok, check} = Ancora.check(root, base: "HEAD")
    assert Enum.any?(check.all_findings, &(&1.code == "change/missing_decision"))
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "docs and standalone tests do not demand a new subject", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")

    for {path, content} <- [
          {"README.md", "Updated usage notes\n"},
          {"test/extra_test.exs",
           "defmodule ExtraTest do\n use ExUnit.Case\n test \"works\", do: assert(true)\nend\n"}
        ] do
      write_files(root, %{path => content})
      assert {:ok, next} = Next.build(root, base: "HEAD")
      assert next.classification == "likely non-contract change"
      assert next.reconciliation == "no contract update needed"
      assert {:ok, check} = Ancora.check(root, base: "HEAD")
      refute check.fail
      File.rm!(Path.join(root, path))
    end
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "a test assertion edit can go straight to check", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")
    path = Path.join(root, "test/sample_test.exs")

    File.write!(
      path,
      String.replace(
        File.read!(path),
        "assert(Sample.value())",
        "assert(Sample.value() == :base)"
      )
    )

    assert {:ok, next} = Next.build(root, base: "HEAD")
    assert next.reconciliation == "ready for check"
    assert {:ok, check} = Ancora.check(root, base: "HEAD")
    refute check.fail
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "governance docs name the missing decision", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")
    write_files(root, %{".spec/README.md" => "Updated corpus guidance\n"})
    assert {:ok, next} = Next.build(root, base: "HEAD")
    assert next.reconciliation == "needs decision update"
    assert {:ok, check} = Ancora.check(root, base: "HEAD")
    assert Enum.any?(check.all_findings, &(&1.code == "change/missing_decision"))
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "configured source paths determine the uncovered files", %{root: root} do
    create_anchored_project(root)
    write_config(root, "lib_paths: [lib, src]\n")
    commit_all(root, "base")
    write_files(root, %{"src/new.ex" => "defmodule New, do: nil\n"})
    assert {:ok, next} = Next.build(root, base: "HEAD")
    assert next.classification == "uncovered frontier change"
    assert "src/new.ex" in next.policy_files
    assert {:ok, check} = Ancora.check(root, base: "HEAD")

    assert Enum.any?(
             check.all_findings,
             &(&1.code == "change/uncovered_file" and &1.file == "src/new.ex")
           )
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "a referenced accepted decision permits a subject update without another ADR", %{
    root: root
  } do
    create_anchored_project(root)
    spec_path = Path.join(root, ".spec/specs/sample.spec.md")

    File.write!(
      spec_path,
      String.replace(
        File.read!(spec_path),
        "status: draft",
        "status: draft\ndecisions: [sample.decision.governance]"
      )
    )

    write_files(root, %{
      ".spec/decisions/governance.md" => """
      ---
      id: sample.decision.governance
      status: accepted
      date: 2026-09-07
      affects: [sample.subject]
      ---
      # Governance
      ## Context
      The sample contract needs an owner.
      ## Decision
      This decision governs the sample subject.
      ## Consequences
      Changes may reference this decision.
      """
    })

    commit_all(root, "governed base")

    File.write!(
      spec_path,
      String.replace(File.read!(spec_path), "return a value", "return the changed value")
    )

    write_files(root, %{"lib/sample.ex" => sample_module(":changed")})

    assert {:ok, next} = Next.build(root, base: "HEAD")
    assert next.reconciliation == "ready for check"
    assert {:ok, check} = Ancora.check(root, base: "HEAD")
    refute check.fail
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "prints uncovered and no-change sibling labels verbatim", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")

    assert {:ok, clean} = Next.build(root, base: "HEAD")
    assert clean.classification == "likely non-contract change"
    assert clean.reconciliation == "no contract update needed"

    write_files(root, %{"lib/frontier.ex" => "defmodule Frontier, do: nil\n"})
    assert {:ok, frontier} = Next.build(root, base: "HEAD")
    assert frontier.classification == "uncovered frontier change"
    assert frontier.reconciliation == "needs new subject"
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "prints cross-cutting and decision labels verbatim", %{root: root} do
    create_two_subject_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/one.ex" => "defmodule One, do: def(value, do: :changed)\n",
      "lib/two.ex" => "defmodule Two, do: def(value, do: :changed)\n",
      ".spec/specs/one.spec.md" => subject_spec("One changed.", "sample.one", "sample.one.works"),
      ".spec/specs/two.spec.md" => subject_spec("Two changed.", "sample.two", "sample.two.works")
    })

    assert {:ok, report} = Next.build(root, base: "HEAD")
    assert report.classification == "covered cross-cutting change"
    assert report.reconciliation == "needs decision update"
  end

  @tag spec: "ancora.tasks.next_labels_verbatim"
  test "uses a supplied status instead of rebuilding it", %{root: root} do
    # Would fail if Next ignored the supplied status and derived the real subject list.
    create_anchored_project(root)
    commit_all(root, "base")
    write_files(root, %{"lib/sample.ex" => sample_module(":changed")})

    assert {:ok, report} = Next.build(root, base: "HEAD", status: %{subjects: []})
    assert report.classification == "uncovered frontier change"
  end

  defp create_anchored_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file(),
      ".spec/specs/sample.spec.md" => subject_spec(),
      "lib/sample.ex" => sample_module(":base"),
      "test/sample_test.exs" => tagged_test("Sample", "sample.subject.works")
    })
  end

  defp create_two_subject_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file(),
      ".spec/specs/one.spec.md" => subject_spec("One works.", "sample.one", "sample.one.works"),
      ".spec/specs/two.spec.md" => subject_spec("Two works.", "sample.two", "sample.two.works"),
      "lib/one.ex" => "defmodule One, do: def(value, do: :base)\n",
      "lib/two.ex" => "defmodule Two, do: def(value, do: :base)\n",
      "test/one_test.exs" => tagged_test("One", "sample.one.works"),
      "test/two_test.exs" => tagged_test("Two", "sample.two.works")
    })
  end

  defp mix_file do
    """
    defmodule Fixture.MixProject do
      use Mix.Project
      def project, do: [app: :fixture]
    end
    """
  end

  defp sample_module(value), do: "defmodule Sample, do: def(value, do: #{value})\n"

  defp tagged_test(module, requirement) do
    """
    defmodule #{module}Test do
      use ExUnit.Case
      @tag spec: "#{requirement}"
      test "works", do: assert(#{module}.value())
    end
    """
  end

  defp subject_spec(
         statement \\ "The sample shall return a value.",
         id \\ "sample.subject",
         requirement \\ "sample.subject.works"
       ) do
    """
    # Sample

    ```yaml spec-meta
    id: #{id}
    kind: module
    status: draft
    ```

    ```yaml spec-requirements
    - id: #{requirement}
      statement: #{statement}
      priority: must
    ```

    ```yaml spec-scenarios
    []
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - #{requirement}
    ```
    """
  end
end
