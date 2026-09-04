Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.GateTest do
  use Ancora.TestCase

  alias Ancora.Gate
  alias Ancora.Gate.Preflight
  alias Ancora.ChangeAnalysis
  alias Ancora.Derive.ChangeSet
  alias Ancora.Git

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight rejects a directory outside git", %{root: root} do
    write_project(root)

    assert {:env, message} = Preflight.run(root, base: "HEAD")
    assert message =~ "not a git repository"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight routes a missing corpus to the environment tier", %{root: root} do
    init_git_repo(root)
    write_files(root, %{"mix.exs" => mix_file("[app: :sample]")})
    commit_all(root, "base")

    assert {:env, message} = Preflight.run(root, base: "HEAD")
    assert message =~ "no .spec/ directory"
    assert message =~ "mix spec.init"
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
    assert message =~ "git exited 128"
    assert message =~ "fatal:"
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

  @tag spec: "ancora.derive.base_reads_batched"
  test "gate materializes only specs, tests, and configured library paths", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/config.yml" => "lib_paths:\n  - src\n",
      ".spec/specs/.keep" => "",
      "src/sample.ex" => "defmodule Sample do\nend\n",
      "lib/decoy.ex" => "defmodule Decoy do\nend\n",
      "test/sample_test.exs" => "defmodule SampleTest do\nend\n",
      "notes/private.txt" => "must not be materialized\n"
    })

    commit_all(root, "base")

    included_oids =
      [".spec/specs/.keep", "src/sample.ex", "test/sample_test.exs"]
      |> Enum.map(&String.trim(git!(root, ["rev-parse", "HEAD:#{&1}"])))
      |> MapSet.new()

    excluded_oids =
      ["lib/decoy.ex", "notes/private.txt"]
      |> Enum.map(&String.trim(git!(root, ["rev-parse", "HEAD:#{&1}"])))

    Code.ensure_loaded!(Git)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Git, :read_blob, 2}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Git, :read_blob, 2}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, _report} = Gate.check(root, base: "HEAD")

    sync_traces(traced, tracer)
    read_objects = collect_git_reads([]) |> MapSet.new()
    assert MapSet.subset?(included_oids, read_objects)

    for oid <- excluded_oids do
      refute MapSet.member?(read_objects, oid)
    end
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "gate materializes a configured spec directory", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      "docs/spec/specs/sample.spec.md" => subject_spec()
    })

    commit_all(root, "base")
    write_files(root, %{".spec/.keep" => ""})

    spec_oid =
      root
      |> git!(["rev-parse", "HEAD:docs/spec/specs/sample.spec.md"])
      |> String.trim()

    Code.ensure_loaded!(Git)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Git, :read_blob, 2}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Git, :read_blob, 2}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, _report} = Gate.check(root, base: "HEAD", spec_dir: "docs/spec")
    sync_traces(traced, tracer)
    assert spec_oid in collect_git_reads([])
  end

  @tag spec: "ancora.derive.memo_is_run_scoped"
  test "gate parses one changed source once per diff side across subjects", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/first.spec.md" =>
        subject_spec("The first value shall be returned.", "sample.first"),
      ".spec/specs/second.spec.md" =>
        subject_spec("The second value shall be returned.", "sample.second"),
      "lib/sample.ex" => """
      defmodule Sample do
        def first, do: :before
        def second, do: :before
      end
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case

        @tag spec: "sample.first.works"
        test "first", do: assert(Sample.first() in [:before, :after])

        @tag spec: "sample.second.works"
        test "second", do: assert(Sample.second() in [:before, :after])
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => """
      defmodule Sample do
        def first, do: :after
        def second, do: :after
      end
      """
    })

    Code.ensure_loaded!(Ancora.Derive.Extract)
    :erlang.trace_pattern({Ancora.Derive.Extract, :parse, 2}, true, [:call_count])

    on_exit(fn ->
      :erlang.trace_pattern({Ancora.Derive.Extract, :parse, 2}, false, [:call_count])
    end)

    assert {:ok, _report} = Gate.check(root, base: "HEAD")

    assert {:call_count, 2} =
             :erlang.trace_info({Ancora.Derive.Extract, :parse, 2}, :call_count)
  end

  @tag spec: "ancora.derive.resolver_is_pure"
  @tag spec: "ancora.gate.no_derived_state"
  test "gate removes its materialized base when an assembly callback raises", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    derive_context = fn _membership, _side, _indexes -> raise "boom" end

    Code.ensure_loaded!(Ancora.BaseView)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])

    :erlang.trace_pattern(
      {Ancora.BaseView, :materialize, 3},
      [{:_, [], [{:return_trace}]}],
      []
    )

    on_exit(fn ->
      :erlang.trace_pattern({Ancora.BaseView, :materialize, 3}, false, [])
      send(tracer, :stop)
    end)

    assert_raise RuntimeError, "boom", fn ->
      Gate.check(root, base: "HEAD", derive_context: derive_context)
    end

    assert_receive {:forwarded_trace,
                    {:trace, _pid, :return_from, {Ancora.BaseView, :materialize, 3},
                     {:ok, temp_root}}}

    refute File.exists?(temp_root)
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

  defp collect_git_reads(objects) do
    receive do
      {:forwarded_trace, {:trace, _pid, :call, {Git, :read_blob, [_ctx, object]}}} ->
        collect_git_reads([object | objects])
    after
      0 -> Enum.reverse(objects)
    end
  end

  defp start_trace_forwarder(parent) do
    spawn(fn -> forward_traces(parent) end)
  end

  defp sync_traces(traced, tracer) do
    delivery_ref = make_ref()
    send(tracer, {:sync, self(), traced, delivery_ref})
    assert_receive {:trace_forwarder_synced, ^delivery_ref}
  end

  defp forward_traces(parent) do
    receive do
      :stop ->
        :ok

      {:sync, caller, traced, caller_ref} ->
        delivery_ref = :erlang.trace_delivered(traced)
        forward_until_delivered(parent, caller, caller_ref, traced, delivery_ref)

      message ->
        send(parent, {:forwarded_trace, message})
        forward_traces(parent)
    end
  end

  defp forward_until_delivered(parent, caller, caller_ref, traced, delivery_ref) do
    receive do
      {:trace_delivered, ^traced, ^delivery_ref} ->
        send(caller, {:trace_forwarder_synced, caller_ref})
        forward_traces(parent)

      message ->
        send(parent, {:forwarded_trace, message})
        forward_until_delivered(parent, caller, caller_ref, traced, delivery_ref)
    end
  end
end
