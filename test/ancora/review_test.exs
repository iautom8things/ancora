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
    assert html =~ "<title>Spec review abc123</title>"
    assert html =~ "generated_at=2026-09-03T18:00:00Z"
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
    refute html =~ "role=\"tablist\""
    refute html =~ "Coverage"
    refute html =~ "triangle"
    refute html =~ "strength"
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  test "keeps authored diff spans outside Prism and lets review CSS win" do
    html = view(:pass, finding("derived/drift", "billing", "lib/billing.ex", "changed"))
    html = html |> Html.render() |> IO.iodata_to_binary()

    assert html =~ "<pre class=\"diff\"><code><span class=\"add\">+def next(value)</span>"
    refute html =~ "class=\"language-diff\""
    assert html =~ ".diff > code > span{display:block}"
    assert html =~ "code{overflow-wrap:anywhere}"

    {prism_css_position, _length} = :binary.match(html, "pre[class*=language-]")
    {review_css_position, _length} = :binary.match(html, ":root{color-scheme:light dark")
    assert prism_css_position < review_css_position
  end

  @tag spec: "ancora.review.findings_inline"
  test "finding summaries name severity and file with a non-colour marker" do
    findings = [
      finding("derived/drift", "billing", "lib/error.ex", "error", :error),
      finding("derived/growth", "billing", "test/warning.exs", "warning", :warning),
      finding("derived/shrink", "billing", nil, "info", :info)
    ]

    view = view(:fail, hd(findings))
    [subject] = view.subjects
    html = %{view | subjects: [%{subject | findings: findings}]} |> Html.render()
    html = IO.iodata_to_binary(html)

    assert html =~
             "<span class=\"severity-marker\" aria-hidden=\"true\">!</span><span class=\"severity-label\">error</span> <code>lib/error.ex</code>"

    assert html =~
             "<span class=\"severity-marker\" aria-hidden=\"true\">~</span><span class=\"severity-label\">warning</span> <code>test/warning.exs</code>"

    assert html =~
             "<span class=\"severity-marker\" aria-hidden=\"true\">i</span><span class=\"severity-label\">info</span> <code>unknown file</code>"
  end

  @tag spec: "ancora.review.code_pivot_grouping"
  @tag spec: "ancora.review.findings_inline"
  test "puts drift under watched interface and growth under test changes" do
    finding =
      finding("derived/drift", "billing", "lib/billing.ex", "billing: Billing.next/1 changed")

    view = view(:fail, finding)
    html = view |> Html.render() |> IO.iodata_to_binary()

    [_before, watched_and_later] = String.split(html, "<h3>Watched interface</h3>", parts: 2)

    [watched_interface, supporting_and_later] =
      String.split(watched_and_later, "<h3>Supporting changes</h3>", parts: 2)

    [_supporting_changes, test_changes] =
      String.split(supporting_and_later, "<h3>Test changes</h3>", parts: 2)

    assert html =~ "class=\"chip fail\""
    assert watched_interface =~ "Billing.next/1"
    assert watched_interface =~ "drift"
    assert watched_interface =~ "lib/billing.ex"
    assert watched_interface =~ "+def next(value)"
    refute watched_interface =~ "Billing.void/2"
    assert test_changes =~ "Billing.void/2"
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

  @tag spec: "ancora.review.findings_delta_without_store"
  test "removed root-reading review entry points stay absent" do
    # Would fail if review restored either path-based compatibility entry point.
    head = %{"requirements" => [], "scenarios" => []}
    spec_diff = Ancora.Review.SpecDiff.compute(head, nil)
    assert spec_diff.base_existed? == false

    Code.ensure_loaded!(Ancora.Review.SpecDiff)
    Code.ensure_loaded!(FindingsDelta)
    refute function_exported?(Ancora.Review.SpecDiff, :compute, 3)
    refute function_exported?(FindingsDelta, :compute, 3)

    assert_raise FunctionClauseError, fn ->
      FindingsDelta.classify("base-root", "head-root", [])
    end
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

    html = built |> Html.render() |> IO.iodata_to_binary()
    assert html =~ "class=\"badge acknowledged\">acknowledged</span>"
  end

  @tag spec: "ancora.review.artifact_size"
  @tag spec: "ancora.review.view_model_builder"
  @tag spec: "ancora.review.code_pivot_grouping"
  test "production builder renders one shared definition diff for three watched subjects", %{
    root: root
  } do
    write_three_subject_project(root)
    commit_all(root, "base")

    write_files(root, %{
      "lib/fixture/shared.ex" => "defmodule Fixture.Shared do\n  def value, do: :changed\nend\n",
      "lib/fixture/helper.ex" =>
        "defmodule Fixture.Helper do\n  @note :changed\n  def bump(value), do: value + 1\nend\n",
      "test/joint_test.exs" => """
      defmodule Fixture.JointTest do
        use ExUnit.Case

        @tag spec: "alpha.next"
        @tag spec: "beta.next"
        test "joint" do
          assert Fixture.Shared.value() in [:shared, :changed]
          assert true
        end
      end
      """
    })

    assert {:ok, built} = Review.build(root, base: "HEAD")

    cards =
      built.subjects
      |> Enum.flat_map(& &1.code.watched_interface)
      |> Enum.filter(&(&1.binding == "Fixture.Shared.value/0"))

    assert length(cards) == 3
    assert Enum.all?(cards, &(&1.badge == :drift))
    assert Enum.count(cards, &(&1.lines != [])) == 1

    html = built |> Html.render() |> IO.iodata_to_binary()
    anchor = "file-lib-fixture-shared-ex"
    watched_card = "<article class=\"watched\"><header><code>Fixture.Shared.value/0"

    assert count_occurrences(html, "+  def value, do: :changed") == 2
    assert count_occurrences(html, "id=\"#{anchor}\"") == 1
    assert count_occurrences(html, "href=\"##{anchor}\"") == 3
    assert count_occurrences(html, watched_card) == 3
    assert count_occurrences(html, "class=\"badge drift\">drift</span>") == 3
    assert count_occurrences(html, "+  @note :changed") == 2
    assert count_occurrences(html, "+    assert true") == 2
    assert count_occurrences(html, "id=\"file-lib-fixture-helper-ex\"") == 1
    assert count_occurrences(html, "<pre class=\"diff\">") == 6
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
      meta: %{
        base_ref: "main",
        head_ref: "abc123",
        generated_at: ~U[2026-09-03 18:00:00Z],
        affected_subjects: 1,
        findings: 1
      },
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

  defp finding(code, subject, file, message, severity \\ :error) do
    %Finding{
      code: code,
      subject: subject,
      file: file,
      message: message,
      severity: severity,
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

  defp write_three_subject_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/alpha.spec.md" => subject_spec("alpha", "alpha value"),
      ".spec/specs/beta.spec.md" => subject_spec("beta", "beta value"),
      ".spec/specs/gamma.spec.md" => subject_spec("gamma", "gamma value"),
      "lib/fixture/shared.ex" => "defmodule Fixture.Shared do\n  def value, do: :shared\nend\n",
      "lib/fixture/helper.ex" =>
        "defmodule Fixture.Helper do\n  def bump(value), do: value + 1\nend\n",
      "test/joint_test.exs" => """
      defmodule Fixture.JointTest do
        use ExUnit.Case

        @tag spec: "alpha.next"
        @tag spec: "beta.next"
        test "joint" do
          assert Fixture.Shared.value() in [:shared, :changed]
        end
      end
      """,
      "test/alpha_test.exs" => """
      defmodule Fixture.AlphaTest do
        use ExUnit.Case

        @tag spec: "alpha.next"
        test "next" do
          assert Fixture.Shared.value() in [:shared, :changed]
          assert Fixture.Helper.bump(1) > 0
        end
      end
      """,
      "test/beta_test.exs" => """
      defmodule Fixture.BetaTest do
        use ExUnit.Case

        @tag spec: "beta.next"
        test "next" do
          assert Fixture.Shared.value() in [:shared, :changed]
          assert Fixture.Helper.bump(1) > 0
        end
      end
      """,
      "test/gamma_test.exs" => """
      defmodule Fixture.GammaTest do
        use ExUnit.Case

        @tag spec: "gamma.next"
        test "next" do
          assert Fixture.Shared.value() in [:shared, :changed]
          assert Fixture.Helper.bump(1) > 0
        end
      end
      """
    })
  end

  defp subject_spec(id, behavior) do
    """
    # #{String.capitalize(id)}

    ```yaml spec-meta
    id: #{id}
    kind: module
    status: draft
    summary: #{String.capitalize(id)} behavior.
    ```

    ```yaml spec-requirements
    - id: #{id}.next
      statement: #{String.capitalize(id)} shall return the #{behavior}.
      priority: must
    ```

    ```yaml spec-scenarios
    []
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - #{id}.next
    ```
    """
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> :binary.matches(needle)
    |> length()
  end
end
