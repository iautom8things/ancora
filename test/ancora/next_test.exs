Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.NextTest do
  use Ancora.TestCase

  alias Ancora.Next

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
  test "prints ready for check after the impacted subject changes", %{root: root} do
    create_anchored_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => sample_module(":changed"),
      ".spec/specs/sample.spec.md" => subject_spec("The sample shall return the changed value.")
    })

    assert {:ok, report} = Next.build(root, base: "HEAD")
    assert report.classification == "covered local change"
    assert report.reconciliation == "ready for check"
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
