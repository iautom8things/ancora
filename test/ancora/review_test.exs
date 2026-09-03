Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ReviewTest do
  use Ancora.TestCase

  alias Ancora.Finding
  alias Ancora.Review
  alias Ancora.Review.FindingsDelta
  alias Ancora.Review.Html

  @tag spec: "ancora.review.views"
  @tag spec: "ancora.review.findings_inline"
  test "renders the master-detail views, green chip, and triage without retired chrome" do
    finding = finding("derived/drift", "billing", "lib/billing.ex", "Billing.next/1 changed")
    view = view(:pass, finding)
    html = view |> Html.render() |> IO.iodata_to_binary()

    assert html =~ "class=\"chip pass\""
    assert html =~ "disableWorkerMessageHandler"
    assert html =~ "code[class*=language-]"
    assert html =~ "Overview"
    assert html =~ "Decisions changed"
    assert html =~ "Outside the spec system"
    assert html =~ "All files"
    assert html =~ "Spec health"
    assert html =~ ">Spec</button>"
    assert html =~ ">Code</button>"
    assert html =~ ">Decisions</button>"
    assert html =~ "derived/drift"
    assert html =~ "Triage"
    refute html =~ "Coverage"
    refute html =~ "triangle"
    refute html =~ "strength"
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  @tag spec: "ancora.review.findings_inline"
  test "puts drift under watched interface and growth under test changes" do
    finding =
      finding("derived/drift", "billing", "lib/billing.ex", "billing: Billing.next/1 changed")

    view = view(:fail, finding)
    html = view |> Html.render() |> IO.iodata_to_binary()

    assert html =~ "class=\"chip fail\""
    assert html =~ "Watched interface"
    assert html =~ "Billing.next/1"
    assert html =~ "drift"
    assert html =~ "lib/billing.ex"
    assert html =~ "+def next(value)"
    assert html =~ "Supporting changes"
    assert html =~ "Test changes"
    assert html =~ "Billing.void/2"
  end

  @tag spec: "ancora.review.findings_delta_without_store"
  test "classifies repo-state findings on both sides and diff findings as introduced" do
    resolved =
      finding("spec/unknown_reference", "billing", ".spec/specs/billing.spec.md", "unknown")

    introduced =
      finding("adr/affects_empty", "billing.adr", ".spec/decisions/billing.md", "empty")

    scoped = finding("derived/growth", "billing", nil, "Billing.void/2")
    shared = finding("spec/title_missing", "billing", ".spec/specs/billing.spec.md", "title")

    delta = FindingsDelta.classify([resolved, shared], [introduced, shared], [scoped])
    stable_delta = FindingsDelta.classify([shared], [shared], [])

    assert delta.resolved == [resolved]
    assert delta.pre_existing == [shared]
    assert Enum.map(delta.introduced, & &1.code) == ["adr/affects_empty", "derived/growth"]
    refute shared in delta.introduced
    assert stable_delta.pre_existing == [shared]
    assert stable_delta.change_verdict.clean?
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  @tag spec: "ancora.review.view_model_builder"
  test "production builder lists a newly called binding under test changes", %{root: root} do
    write_project(root)

    write_files(root, %{
      "lib/billing.ex" =>
        "defmodule Billing do\n  def next(value), do: value\n  def void(value, reason), do: {value, reason}\nend\n"
    })

    commit_all(root, "base")

    write_files(root, %{
      "test/billing_test.exs" => """
      defmodule BillingTest do
        use ExUnit.Case
        @tag spec: "billing.next"
        test "next and void" do
          assert Billing.next(1) == 1
          assert Billing.void(1, :duplicate) == {1, :duplicate}
        end
      end
      """
    })

    assert {:ok, built} = Review.build(root, base: "HEAD")
    assert [subject] = built.subjects
    assert subject.code.added_bindings == ["Billing.void/2"]

    html = built |> Html.render() |> IO.iodata_to_binary()
    [_before, test_changes] = String.split(html, "<h3>Test changes</h3>", parts: 2)

    assert test_changes =~ "Added bindings"
    assert test_changes =~ "Billing.void/2"
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  @tag spec: "ancora.review.view_model_builder"
  test "production builder groups an actual derived drift card", %{root: root} do
    write_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/billing.ex" => "defmodule Billing do\n  def next(value), do: value + 1\nend\n"
    })

    assert {:ok, built} = Review.build(root, base: "HEAD")
    assert [subject] = built.subjects
    assert [%{binding: "Billing.next/1", badge: :drift}] = subject.code.watched_interface
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  @tag spec: "ancora.review.view_model_builder"
  test "production builder keeps an acknowledged body change in the watched interface", %{
    root: root
  } do
    write_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/billing.ex" => "defmodule Billing do\n  def next(value), do: value + 1\nend\n",
      ".spec/specs/billing.spec.md" =>
        Path.join(root, ".spec/specs/billing.spec.md")
        |> File.read!()
        |> String.replace("return the next value", "increment the supplied value")
    })

    assert {:ok, built} = Review.build(root, base: "HEAD")
    assert [subject] = built.subjects

    assert [%{binding: "Billing.next/1", badge: :acknowledged}] =
             subject.code.watched_interface
  end

  defp view(verdict, finding) do
    subject = %{
      id: "billing",
      title: "Billing",
      summary: "Owns [[billing.invoice]].",
      file: ".spec/specs/billing.spec.md",
      requirements: [%{id: "billing.next", statement: "Returns the next value."}],
      scenarios: [%{id: "billing.scenario.next"}],
      decision_refs: ["billing.invoice"],
      findings: [finding],
      spec_diff: %{},
      code: %{
        watched_interface: [
          %{
            binding: "Billing.next/1",
            badge: :drift,
            file: "lib/billing.ex",
            lines: [{:add, "+def next(value)"}]
          }
        ],
        supporting_changes: [%{file: "lib/support.ex", lines: [{:add, "+def help"}]}],
        test_changes: [%{file: "test/billing_test.exs", lines: [{:add, "+test next"}]}],
        added_bindings: ["Billing.void/2"],
        removed_bindings: []
      }
    }

    delta = FindingsDelta.classify([], [finding])

    %{
      meta: %{base_ref: "main", head_ref: "abc123", affected_subjects: 1, findings: 1},
      verdict: verdict,
      findings_delta: delta,
      triage: %{error: [finding]},
      subjects: [subject],
      decisions_changed: [],
      outside_changes: [],
      all_changes: [],
      spec_health: %{subjects: 1, requirements: 1, errors: 0, warnings: 0}
    }
  end

  defp finding(code, subject, file, message) do
    %Finding{
      code: code,
      subject: subject,
      file: file,
      message: message,
      severity: :error,
      severity_source: :default
    }
  end

  defp write_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/billing.spec.md" => """
      # Billing

      ```yaml spec-meta
      id: billing
      kind: module
      status: draft
      summary: Billing behavior.
      ```

      ```yaml spec-requirements
      - id: billing.next
        statement: Billing shall return the next value.
        priority: must
      ```

      ```yaml spec-scenarios
      []
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - billing.next
      ```
      """,
      "lib/billing.ex" => "defmodule Billing do\n  def next(value), do: value\nend\n",
      "test/billing_test.exs" => """
      defmodule BillingTest do
        use ExUnit.Case
        @tag spec: "billing.next"
        test "next" do
          assert Billing.next(1) in [1, 2]
        end
      end
      """
    })
  end
end
