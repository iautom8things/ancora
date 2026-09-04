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
  test "changed source under configured lib_paths is reported", %{root: root} do
    # Would fail if uncovered-file analysis used hardcoded source prefixes instead of the
    # project paths resolved by preflight.
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/config.yml" => "lib_paths:\n  - src\n",
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")
    write_files(root, %{"src/thing.ex" => "defmodule Thing do\nend\n"})

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "change/uncovered_file" and finding.file == "src/thing.ex"
           end)
  end

  @tag spec: "ancora.derive.project_info_from_root"
  @tag spec: "ancora.derive.membership_source_derived"
  @tag spec: "ancora.derive.subject_footprint"
  test "tagged source under a trailing-slash lib path stays covered", %{root: root} do
    # Would fail if a trailing-slash lib_path reached ChangeAnalysis untrimmed:
    # src/other.ex would silently leave uncovered-file scope. The tagged
    # src/thing.ex half documents the covered case but does not discriminate the fix.
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/config.yml" => "lib_paths:\n  - src/\n",
      ".spec/specs/thing.spec.md" => subject_spec("Thing shall return its value.", "thing.value"),
      "src/other.ex" => "defmodule Other do\n  def value, do: :base\nend\n",
      "src/thing.ex" => "defmodule Thing do\n  def value, do: :base\nend\n",
      "test/thing_test.exs" => """
      defmodule ThingTest do
        use ExUnit.Case
        @tag spec: "thing.value.works"
        test "value", do: assert(Thing.value() in [:base, :changed])
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "src/other.ex" => "defmodule Other do\n  def value, do: :changed\nend\n",
      "src/thing.ex" => "defmodule Thing do\n  def value, do: :changed\nend\n"
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.subject == "thing.value"
           end)

    refute Enum.any?(report.all_findings, fn finding ->
             finding.code == "change/uncovered_file" and finding.file == "src/thing.ex"
           end)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "change/uncovered_file" and finding.file == "src/other.ex"
           end)
  end

  @tag spec: "ancora.gate.change_findings"
  test "changed files outside lib_paths are not reported", %{root: root} do
    # Would fail if uncovered-file analysis treated priv assets as source or matched a
    # directory name without requiring a path boundary.
    create_clean_repo(root)

    write_files(root, %{
      "priv/assets/app.js" => "export default {};\n",
      "library.ex" => "defmodule Library do\nend\n"
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    for path <- ["priv/assets/app.js", "library.ex"] do
      refute Enum.any?(report.all_findings, fn finding ->
               finding.code == "change/uncovered_file" and finding.file == path
             end)
    end
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
  test "an existing bidirectional ADR governs repeated subject spec changes", %{root: root} do
    init_git_repo(root)

    write_governed_subject(
      root,
      "The sample shall return the initial value.",
      "sample.decision.governance",
      "sample.subject"
    )

    commit_all(root, "base")

    write_governed_subject(
      root,
      "The sample shall return the first changed value.",
      "sample.decision.governance",
      "sample.subject"
    )

    assert {:ok, first_report} = Gate.check(root, base: "HEAD")
    refute missing_decision?(first_report, ".spec/specs/sample.spec.md")

    commit_all(root, "first governed spec change")

    write_governed_subject(
      root,
      "The sample shall return the second changed value.",
      "sample.decision.governance",
      "sample.subject"
    )

    assert {:ok, second_report} = Gate.check(root, base: "HEAD")
    refute missing_decision?(second_report, ".spec/specs/sample.spec.md")
  end

  @tag spec: "ancora.gate.change_findings"
  test "a one-way subject decision reference does not provide governance", %{root: root} do
    init_git_repo(root)

    write_governed_subject(
      root,
      "The sample shall return the initial value.",
      "sample.decision.governance",
      "sample.decision.governance"
    )

    commit_all(root, "base")

    write_governed_subject(
      root,
      "The sample shall return the changed value.",
      "sample.decision.governance",
      "sample.decision.governance"
    )

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "change/missing_decision" and
               finding.file == ".spec/specs/sample.spec.md" and
               finding.message =~ "decisions: frontmatter" and
               finding.message =~ "affects: naming the subject back" and
               finding.message =~ "add or update an ADR"
           end)
  end

  @tag spec: "ancora.gate.change_findings"
  test "a spec cannot claim governance from an ADR it does not cite", %{root: root} do
    init_git_repo(root)

    write_governed_subject(
      root,
      "The sample shall return the initial value.",
      "sample.decision.other",
      "sample.subject"
    )

    write_files(root, %{
      ".spec/decisions/other.md" =>
        governing_decision("sample.decision.other", "sample.decision.other")
    })

    commit_all(root, "base")

    write_governed_subject(
      root,
      "The sample shall return the changed value.",
      "sample.decision.other",
      "sample.subject"
    )

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert missing_decision?(report, ".spec/specs/sample.spec.md")
  end

  @tag spec: "ancora.gate.change_findings"
  test "frontmatter-less governance files still require a co-changed ADR", %{root: root} do
    init_git_repo(root)

    write_governed_subject(
      root,
      "The sample shall return the initial value.",
      "sample.decision.governance",
      "sample.subject"
    )

    commit_all(root, "base")

    write_governed_subject(
      root,
      "The sample shall return the changed value.",
      "sample.decision.governance",
      "sample.subject"
    )

    write_config(root, "default_base: main\n")

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    assert missing_decision?(report, ".spec/config.yml")
    refute missing_decision?(report, ".spec/specs/sample.spec.md")
  end

  @tag spec: "ancora.gate.change_findings"
  test "requirement and scenario ADR back-references govern their subject" do
    change_set = %ChangeSet{
      entries: [%{path: ".spec/specs/sample.spec.md", status: :modified}]
    }

    for affected_id <- ["sample.subject.works", "sample.subject.scenario.works"] do
      current = governed_index(affected_id)

      refute Enum.any?(
               ChangeAnalysis.findings(change_set, %{}, current, current, %{head: %{}, base: %{}}),
               &(&1.code == "change/missing_decision")
             )
    end
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
               %{head: %{}, base: %{}}
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
  @tag spec: "ancora.findings.severity_precedence"
  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  @tag spec: "ancora.gate.statement_change_disclosed"
  test "a substantive spec edit retains production drift as an acknowledged info", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n",
      ".spec/specs/sample.spec.md" => subject_spec("The sample shall return the changed value."),
      "test/second_sample_test.exs" => """
      defmodule SecondSampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "second binding", do: assert(Sample.value() == :changed)
      end
      """
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.severity == :info and
               finding.severity_source == :ack
           end)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "append/statement_changed" and
               finding.requirement == "sample.subject.works"
           end)

    refute Enum.any?(report.all_findings, &(&1.code == "tags/tag_borrowed"))
  end

  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  test "a new tag on an unchanged existing requirement is disclosed", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(),
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :current\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        test "works", do: assert(Sample.value() == :current)
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() == :current)
      end
      """
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "tags/tag_borrowed" and
               finding.file == "test/sample_test.exs" and
               finding.requirement == "sample.subject.works" and finding.severity == :info
           end)
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "a substantive spec edit acknowledges transitive drift", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" =>
        subject_spec("The sample shall return the current value.", "sample.subject", []),
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :current\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() in [:current, :changed])
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n",
      ".spec/specs/sample.spec.md" =>
        subject_spec("The sample shall return the changed value.", "sample.subject", [])
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift_transitive" and finding.severity == :info and
               finding.severity_source == :ack
           end)
  end

  @tag spec: "ancora.derive.drift_primary_transitive"
  @tag spec: "ancora.gate.diff_scoped_versus_repo_state"
  test "surface fan-out reports exactly K primary and N-K transitive drift", %{root: root} do
    init_git_repo(root)

    specs =
      for {name, surface} <- [{"one", ["lib/shared.ex"]}, {"two", []}, {"three", []}],
          into: %{} do
        {".spec/specs/#{name}.spec.md", shared_subject_spec(name, surface)}
      end

    tests =
      for name <- ["one", "two", "three"], into: %{} do
        {"test/#{name}_test.exs", shared_test(name)}
      end

    write_files(
      root,
      Map.merge(specs, tests)
      |> Map.merge(%{
        "mix.exs" => mix_file("[app: :sample]"),
        "lib/shared.ex" => "defmodule Shared do\n  def value, do: :base\nend\n"
      })
    )

    commit_all(root, "base")

    write_files(root, %{
      "lib/shared.ex" => "defmodule Shared do\n  def value, do: :changed\nend\n"
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")
    drift = Enum.filter(report.all_findings, &String.starts_with?(&1.code, "derived/drift"))

    assert Enum.count(drift, &(&1.code == "derived/drift")) == 1
    assert Enum.count(drift, &(&1.code == "derived/drift_transitive")) == 2
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
  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  test "a new subject acknowledges its own growth", %{root: root} do
    create_clean_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/growth" and finding.severity == :info and
               finding.severity_source == :ack
           end)

    refute Enum.any?(report.all_findings, &(&1.code == "tags/tag_borrowed"))
  end

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

  @tag spec: "ancora.findings.per_subject_overrides"
  test "rejects an override for a requirement outside the indexed corpus", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(),
      ".spec/config.yml" => """
      overrides:
        - subject: sample.subject
          requirement: sample.subject.missing
          code: tags/requirement_untagged
          severity: warning
          reason: requirement does not exist
      """
    })

    commit_all(root, "base")

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "config/invalid_value" and
               finding.message =~ "sample.subject.missing"
           end)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "tags/requirement_untagged" and
               finding.requirement == "sample.subject.works" and
               finding.severity == :info and finding.severity_source == :default
           end)
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

  defp write_governed_subject(root, statement, decision_id, affected_id) do
    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => governed_subject_spec(statement, decision_id),
      ".spec/decisions/governance.md" =>
        governing_decision("sample.decision.governance", affected_id),
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :current\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() == :current)
      end
      """
    })
  end

  defp missing_decision?(report, path) do
    Enum.any?(report.all_findings, fn finding ->
      finding.code == "change/missing_decision" and finding.file == path
    end)
  end

  defp governed_index(affected_id) do
    %{
      "subjects" => [
        %{
          "file" => ".spec/specs/sample.spec.md",
          "meta" => %{id: "sample.subject", decisions: ["sample.decision.governance"]},
          "requirements" => [%{id: "sample.subject.works"}],
          "scenarios" => [%{id: "sample.subject.scenario.works"}]
        }
      ],
      "decisions" => [
        %{
          "meta" => %{
            "id" => "sample.decision.governance",
            "affects" => [affected_id]
          }
        }
      ]
    }
  end

  defp mix_file(project) do
    """
    defmodule Sample.MixProject do
      use Mix.Project
      def project, do: #{project}
    end
    """
  end

  defp subject_spec(
         statement \\ "The sample shall work.",
         subject \\ "sample.subject",
         surface \\ nil
       ) do
    surface_block = if is_list(surface), do: "surface: #{inspect(surface)}\n", else: ""

    """
    # Sample

    ```yaml spec-meta
    id: #{subject}
    kind: module
    status: draft
    #{surface_block}```

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

  defp governed_subject_spec(statement, decision_id) do
    """
    # Sample

    ```yaml spec-meta
    id: sample.subject
    kind: module
    status: draft
    decisions:
      - #{decision_id}
    ```

    ```yaml spec-requirements
    - id: sample.subject.works
      statement: #{statement}
      priority: must
    ```

    ```yaml spec-scenarios
    - id: sample.subject.scenario.works
      given:
        - a sample
      when:
        - its value is read
      then:
        - the current value is returned
      covers:
        - sample.subject.works
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - sample.subject.works
    ```
    """
  end

  defp shared_subject_spec(name, surface) do
    surface_lines = Enum.map_join(surface, "\n", &"  - #{&1}")
    surface_block = if surface == [], do: "surface: []", else: "surface:\n#{surface_lines}"

    """
    # #{name}

    ```yaml spec-meta
    id: shared.#{name}
    kind: module
    status: draft
    #{surface_block}
    ```

    ```yaml spec-requirements
    - id: shared.#{name}.works
      statement: Shared shall return a value for #{name}.
      priority: must
    ```

    ```yaml spec-scenarios
    []
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - shared.#{name}.works
    ```
    """
  end

  defp shared_test(name) do
    module = name |> String.capitalize() |> Kernel.<>("Test")

    """
    defmodule #{module} do
      use ExUnit.Case
      @tag spec: "shared.#{name}.works"
      test "shared value", do: assert(Shared.value() in [:base, :changed])
    end
    """
  end

  defp governing_decision(decision_id, affected_id) do
    """
    ---
    id: #{decision_id}
    status: accepted
    date: 2026-09-03
    affects:
      - #{affected_id}
    ---

    # Sample governance

    ## Context

    The sample contract needs an explicit owner.

    ## Decision

    This ADR governs the sample contract.

    ## Consequences

    Subject changes may cite this ADR.
    """
  end
end
