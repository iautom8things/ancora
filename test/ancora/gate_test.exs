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
  test "info-only unanchored finding is hidden and does not fail", %{root: root} do
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
      """,
      ".spec/config.yml" => """
      overrides:
        - subject: sample.subject
          code: derived/unanchored_subject
          severity: info
          reason: integration-only contract
      """
    })

    commit_all(root, "base")
    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert report.fail == false
    assert report.findings == []
    assert report.branch.info >= 1

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/unanchored_subject" and finding.severity == :info
           end)
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

  defp subject_spec(statement \\ "The sample shall work.") do
    """
    # Sample

    ```yaml spec-meta
    id: sample.subject
    kind: module
    status: draft
    ```

    ```yaml spec-requirements
    - id: sample.subject.works
      statement: #{statement}
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
  end
end
