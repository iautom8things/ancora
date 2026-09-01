Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.GateTest do
  use Ancora.TestCase

  alias Ancora.Gate
  alias Ancora.Gate.Preflight
  alias Ancora.ChangeAnalysis
  alias Ancora.Derive.ChangeSet

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight rejects a directory outside git", %{root: root} do
    write_project(root)

    assert {:env, message} = Preflight.run(root, base: "HEAD")
    assert message =~ "not a git repository"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight turns umbrella and dynamic app signals into env failures", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample, apps_path: \"apps\"]"),
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")
    assert {:env, umbrella} = Preflight.run(root, base: "HEAD")
    assert umbrella =~ "umbrella roots are not supported"

    write_files(root, %{"mix.exs" => mix_file("[app: app_name()]")})
    assert {:env, dynamic_app} = Preflight.run(root, base: "HEAD")
    assert dynamic_app =~ "app: as a literal atom"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  @tag spec: "ancora.derive.project_info_from_root"
  test "preflight preserves literal elixirc paths unless config overrides them", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample, elixirc_paths: [\"lib\", \"extra\"]]"),
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")

    assert {:ok, preflight} = Preflight.run(root, base: "HEAD")
    assert preflight.project.lib_paths == ["lib", "extra"]

    write_config(root, "lib_paths:\n  - src\n")
    assert {:ok, overridden} = Preflight.run(root, base: "HEAD")
    assert overridden.project.lib_paths == ["src"]
  end

  @tag spec: "ancora.gate.default_base_no_fallback"
  test "missing default base names every remedy", %{root: root} do
    create_clean_repo(root)

    assert {:env, message} = Preflight.run(root)
    assert message =~ "git fetch origin main"
    assert message =~ "--base <ref>"
    assert message =~ "default_base"
  end

  @tag spec: "ancora.gate.default_base_no_fallback"
  @tag spec: "ancora.gate.diff_scoped_versus_repo_state"
  @tag spec: "ancora.gate.strict_verdict"
  test "HEAD is a legal empty diff and an empty corpus passes", %{root: root} do
    create_clean_repo(root)

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert report.fail == false
    assert report.checked.subjects == 0
    assert report.branch.changed_files == 0
    assert report.findings == []
  end

  @tag spec: "ancora.gate.change_findings"
  test "changed source outside every derived footprint is reported", %{root: root} do
    create_clean_repo(root)
    write_files(root, %{"lib/new_thing.ex" => "defmodule NewThing do\nend\n"})

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert Enum.any?(report.all_findings, &(&1.code == "change/uncovered_file"))
  end

  @tag spec: "ancora.gate.change_findings"
  test "governance change without an ADR is reported through the gate", %{root: root} do
    create_clean_repo(root)
    write_config(root, "default_base: main\n")

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "change/missing_decision" and finding.file == ".spec/config.yml"
           end)
  end

  @tag spec: "ancora.gate.change_findings"
  test "change analysis is wired to the production change set" do
    change_set = %ChangeSet{entries: [%{path: "lib/new_thing.ex", status: :added}]}

    assert [%{code: "change/uncovered_file", file: "lib/new_thing.ex"}] =
             ChangeAnalysis.findings(
               change_set,
               %{},
               %{"subjects" => []},
               %{"subjects" => []},
               []
             )
  end

  @tag spec: "ancora.gate.no_derived_state"
  test "gate does not write derived state", %{root: root} do
    create_clean_repo(root)
    assert {:ok, _report} = Gate.check(root, base: "HEAD")
    refute File.exists?(Path.join(root, ".spec/state.json"))
    refute File.exists?(Path.join(root, ".spec/realization_hashes.json"))
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "a substantive spec edit clears production drift", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n",
      ".spec/specs/sample.spec.md" => subject_spec("The sample shall return the changed value.")
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    refute Enum.any?(report.all_findings, &(&1.code == "derived/drift"))
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "a Spec-Ack trailer downgrades drift without hiding it", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")

    assert {:ok, report} = Gate.check(root, base: "HEAD~1")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.severity == :info and
               finding.severity_source == :trailer
           end)

    assert report.fail == false
  end

  @tag spec: "ancora.gate.new_subject_self_clears"
  test "a new subject clears its own growth", %{root: root} do
    create_clean_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    refute Enum.any?(report.all_findings, &(&1.code == "derived/growth"))
  end

  @tag spec: "ancora.derive.change_set_union"
  @tag spec: "ancora.derive.growth_and_shrink"
  test "a tagged test in a new untracked directory produces growth", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/billing.spec.md" =>
        subject_spec("Billing shall expose its operations.", "billing.operations"),
      "lib/billing.ex" => """
      defmodule Billing do
        def next(value), do: value
        def void(left, right), do: {left, right}
      end
      """,
      "test/billing_test.exs" => """
      defmodule BillingTest do
        use ExUnit.Case
        @tag spec: "billing.operations.works"
        test "next", do: assert(Billing.next(:invoice) == :invoice)
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "test/billing/void_test.exs" => """
      defmodule Billing.VoidTest do
        use ExUnit.Case
        @tag spec: "billing.operations.works"
        test "void", do: assert(Billing.void(:left, :right) == {:left, :right})
      end
      """
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/growth" and
               finding.subject == "billing.operations" and
               finding.message =~ "Billing.void/2"
           end)
  end

  @tag spec: "ancora.derive.parse_degrades_to_finding"
  test "an unparseable production file becomes a finding", %{root: root} do
    create_clean_repo(root)
    write_files(root, %{"lib/broken.ex" => "defmodule Broken do\n  def nope(\nend\n"})

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/unparseable_source" and finding.file == "lib/broken.ex"
           end)
  end

  @tag spec: "ancora.findings.info_visibility"
  @tag spec: "ancora.gate.unanchored_subject"
  test "an override changes only its unanchored subject", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/a.spec.md" => subject_spec("The first sample shall work.", "sample.a"),
      ".spec/specs/b.spec.md" => subject_spec("The second sample shall work.", "sample.b"),
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.a.works"
        test "a works", do: assert(true)

        @tag spec: "sample.b.works"
        test "b works", do: assert(true)
      end
      """,
      ".spec/config.yml" => """
      overrides:
        - subject: sample.a
          code: derived/unanchored_subject
          severity: info
          reason: integration-only contract
      """
    })

    commit_all(root, "base")
    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert report.fail == true

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/unanchored_subject" and finding.subject == "sample.a" and
               finding.severity == :info
           end)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/unanchored_subject" and finding.subject == "sample.b" and
               finding.severity == :warning
           end)

    refute Enum.any?(report.findings, &(&1.subject == "sample.a"))
  end

  @tag spec: "ancora.gate.unanchored_subject"
  test "an unanchored subject fires on every unchanged run with its override remedy", %{
    root: root
  } do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(),
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(true)
      end
      """
    })

    commit_all(root, "base")

    for _run <- 1..2 do
      assert {:ok, report} = Gate.check(root, base: "HEAD")

      assert Enum.any?(report.all_findings, fn finding ->
               finding.code == "derived/unanchored_subject" and
                 finding.message =~ "overrides:"
             end)
    end
  end

  defp create_clean_repo(root) do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "base")
  end

  defp write_project(root) do
    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/.keep" => ""
    })
  end

  defp write_anchored_subject(root, statement) do
    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(statement),
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :current\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() in [:current, :changed])
      end
      """
    })
  end

  defp mix_file(project) do
    """
    defmodule Sample.MixProject do
      use Mix.Project
      def project, do: #{project}
    end
    """
  end

  defp subject_spec(statement \\ "The sample shall work.", subject \\ "sample.subject") do
    """
    # Sample

    ```yaml spec-meta
    id: #{subject}
    kind: module
    status: draft
    ```

    ```yaml spec-requirements
    - id: #{subject}.works
      statement: #{statement}
      priority: must
    ```

    ```yaml spec-scenarios
    []
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - #{subject}.works
    ```
    """
  end
end
