Code.require_file("../support/ancora_case.exs", __DIR__)
Code.require_file("../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.GateTest do
  use Ancora.TestCase, async: false

  alias Ancora.Gate
  alias Ancora.Gate.Preflight
  alias Ancora.ChangeAnalysis
  alias Ancora.Derive.ChangeSet
  alias Ancora.Git
  alias Ancora.TmpGitRepo

  @tag spec: "ancora.derive.base_reads_batched"
  test "gate propagates an unsafe base tree as an environment failure" do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)

    TmpGitRepo.write!(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/.keep" => ""
    })

    TmpGitRepo.commit!(root, "head")
    base = TmpGitRepo.commit_tree_path!(root, ["lib", "..", "evil.txt"])

    assert {:env, message} = Gate.check(root, base: base)
    assert message =~ "unsafe base tree path"
    assert message =~ "lib/../evil.txt"
  end

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

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight rejects a shallow boundary inside base..HEAD", %{root: root} do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "middle one\n"})
    commit_all(root, "middle one")
    write_files(root, %{"README.md" => "middle two\n"})
    commit_all(root, "middle two")
    missing_parent = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "head\n"})
    commit_all(root, "head")

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    {_output, status} =
      System.cmd("git", ["-C", shallow, "cat-file", "-e", "#{missing_parent}^{commit}"],
        stderr_to_stdout: true
      )

    assert status != 0

    assert {:env, message} = Gate.check(shallow, base: base)
    assert message =~ "base..HEAD history is incomplete"
    assert message =~ "git fetch --unshallow"
    assert message =~ "fetch-depth: 0"
  end

  @tag spec: "ancora.derive.change_set_union"
  test "an incomplete shallow range stops before change set computation", %{root: root} do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "middle one\n"})
    commit_all(root, "middle one")
    write_files(root, %{"README.md" => "middle two\n"})
    commit_all(root, "middle two")
    write_files(root, %{"README.md" => "head\n"})
    commit_all(root, "head")

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    Code.ensure_loaded!(ChangeSet)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])
    assert :erlang.trace_pattern({ChangeSet, :compute, 1}, true, []) == 1

    on_exit(fn ->
      :erlang.trace_pattern({ChangeSet, :compute, 1}, false, [])
      send(tracer, :stop)
    end)

    assert {:env, _message} = Gate.check(shallow, base: base)
    sync_traces(traced, tracer)

    refute_received {:forwarded_trace, {:trace, ^traced, :call, {ChangeSet, :compute, [_ctx]}}}
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight accepts a depth-one clone after its parent arrives", %{root: root} do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "head\n"})
    commit_all(root, "head")

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    assert TmpGitRepo.git!(shallow, ["rev-parse", "--is-shallow-repository"]) |> String.trim() ==
             "true"

    assert {:ok, preflight} = Preflight.run(shallow, base: base)
    assert preflight.base == base
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight reads parents from the commit header, not the message body", %{root: root} do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "head\n"})

    commit_all(
      root,
      "head\n\nparent 0000000000000000000000000000000000000000\nparent pom bumped\n"
    )

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    assert TmpGitRepo.git!(shallow, ["rev-parse", "--is-shallow-repository"]) |> String.trim() ==
             "true"

    assert TmpGitRepo.git!(shallow, ["show", "-s", "--format=%B", "HEAD"]) =~
             "parent 0000000000000000000000000000000000000000"

    assert {:ok, preflight} = Preflight.run(shallow, base: base)
    assert preflight.base == base
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight accepts a shallow clone when it contains the whole range", %{root: root} do
    init_git_repo(root)
    write_project(root)
    commit_all(root, "older")
    write_files(root, %{"README.md" => "base\n"})
    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    write_files(root, %{"README.md" => "head\n"})
    commit_all(root, "head")

    shallow = TmpGitRepo.shallow_clone!(root, depth: 2)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)

    assert TmpGitRepo.git!(shallow, ["rev-parse", "--is-shallow-repository"]) |> String.trim() ==
             "true"

    assert {:ok, preflight} = Preflight.run(shallow, base: base)
    assert preflight.base == base
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

  @tag spec: "ancora.gate.no_derived_state"
  test "gate creates no ETS tables during a run", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, :set_on_spawn, {:tracer, tracer}])
    :erlang.trace_pattern({:ets, :new, 2}, true, [])
    :erlang.trace_pattern({:ets, :delete, 1}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({:ets, :new, 2}, false, [])
      :erlang.trace_pattern({:ets, :delete, 1}, false, [])
      send(tracer, :stop)
    end)

    tables_before = length(:ets.all())
    assert {:ok, _report} = Gate.check(root, base: "HEAD")
    sync_traces(traced, tracer)
    assert collect_ets_calls([]) == []
    assert length(:ets.all()) == tables_before
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

  @tag spec: "ancora.derive.change_set_union"
  test "gate detects drift in a UTF-8 library path", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(),
      "lib/café.ex" => "defmodule Sample do\n  def value, do: :before\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() in [:before, :after])
      end
      """
    })

    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/café.ex" => "defmodule Sample do\n  def value, do: :after\nend\n"
    })

    assert {:ok, report} = Gate.check(root, base: base)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.file == "lib/café.ex" and
               finding.subject == "sample.subject"
           end)
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "change-set prefetch resolves a spaced path to its base OID", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec(),
      "lib/my sample.ex" => "defmodule Sample do\n  def value, do: :before\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() in [:before, :after])
      end
      """
    })

    commit_all(root, "base")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    oid = root |> git!(["rev-parse", "#{base}:lib/my sample.ex"]) |> String.trim()

    write_files(root, %{
      "lib/my sample.ex" => "defmodule Sample do\n  def value, do: :after\nend\n"
    })

    Code.ensure_loaded!(Git)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Git, :read_blob, 2}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Git, :read_blob, 2}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, report} = Gate.check(root, base: base)

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.file == "lib/my sample.ex" and
               finding.subject == "sample.subject"
           end)

    sync_traces(traced, tracer)
    assert {:oid, oid} in collect_git_reads([])
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

  @tag spec: "ancora.derive.memo_is_run_scoped"
  test "gate reuses the module locator AST when building definition indexes", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    source = "defmodule Sample do\n  def value, do: :current\nend\n"
    Code.ensure_loaded!(Code)
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, :set_on_spawn, {:tracer, tracer}])
    :erlang.trace_pattern({Code, :string_to_quoted, 2}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Code, :string_to_quoted, 2}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, _report} = Gate.check(root, base: "HEAD")
    sync_traces(traced, tracer)

    assert count_source_parses(source, 0) == 1,
           "Would fail if the DefIndex leg read and parsed a lib file after ModuleLocator had already parsed it"
  end

  @tag spec: "ancora.derive.parse_degrades_to_finding"
  test "parallel parsing preserves complete finding order across runs", %{root: root} do
    create_clean_repo(root)

    slow_spec =
      String.duplicate("Spec parser padding.\n", 20_000) <>
        subject_spec("Alpha shall work.", "alpha.subject")

    slow_error =
      "defmodule SlowErrorTest do\n" <>
        String.duplicate("  @tag :padding\n", 20_000) <>
        "  test(\nend\n"

    write_files(root, %{
      ".spec/specs/a_alpha.spec.md" => slow_spec,
      ".spec/specs/b_beta.spec.md" => subject_spec("Beta shall work.", "beta.subject"),
      ".spec/specs/c_gamma.spec.md" => subject_spec("Gamma shall work.", "gamma.subject"),
      ".spec/specs/d_delta.spec.md" => subject_spec("Delta shall work.", "delta.subject"),
      "lib/alpha.ex" => "defmodule Alpha do\n  def value, do: :alpha\nend\n",
      "lib/beta.ex" => "defmodule Beta do\n  def value, do: :beta\nend\n",
      "lib/gamma.ex" => "defmodule Gamma do\n  def value, do: :gamma\nend\n",
      "test/a_slow_error_test.exs" => slow_error,
      "test/z_fast_error_test.exs" => "defmodule FastErrorTest do\n  test(\nend\n"
    })

    finding_lists =
      for _run <- 1..10 do
        assert {:ok, report} = Gate.check(root, base: "HEAD")
        report.all_findings
      end

    assert Enum.all?(tl(finding_lists), &(&1 == hd(finding_lists)))

    assert finding_lists
           |> hd()
           |> Enum.filter(&(&1.code == "tags/requirement_untagged"))
           |> Enum.map(&{&1.subject, &1.code}) ==
             [
               {"alpha.subject", "tags/requirement_untagged"},
               {"beta.subject", "tags/requirement_untagged"},
               {"gamma.subject", "tags/requirement_untagged"},
               {"delta.subject", "tags/requirement_untagged"}
             ],
           "Would fail if spec parse results were collected outside path order"

    assert finding_lists
           |> hd()
           |> Enum.filter(&(&1.code == "tags/parse_error"))
           |> Enum.map(& &1.file) ==
             ["test/a_slow_error_test.exs", "test/z_fast_error_test.exs"],
           "Would fail if parallel parse results were collected in task completion order"
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
  @tag spec: "ancora.findings.severity_precedence"
  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  @tag spec: "ancora.gate.statement_change_disclosed"
  test "a substantive spec edit acknowledges drift, growth, and shrink at info", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" =>
        subject_spec("The sample shall return the current and legacy values."),
      "lib/sample.ex" => """
      defmodule Sample do
        def value, do: :current
        def legacy, do: :legacy
      end
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works" do
          assert Sample.value() == :current
          assert Sample.legacy() == :legacy
        end
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      ".spec/specs/sample.spec.md" =>
        subject_spec("The sample shall return the changed and replacement values."),
      "lib/sample.ex" => """
      defmodule Sample do
        def value, do: :changed
        def legacy, do: :legacy
        def replacement, do: :replacement
      end
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works" do
          assert Sample.value() == :changed
          assert Sample.replacement() == :replacement
        end
      end
      """,
      "test/second_sample_test.exs" => """
      defmodule SecondSampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "second binding", do: assert(Sample.value() == :changed)
      end
      """
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    acked =
      Enum.filter(
        report.all_findings,
        &(&1.code in ["derived/drift", "derived/growth", "derived/shrink"])
      )

    assert Enum.map(acked, & &1.code) |> Enum.sort() ==
             ["derived/drift", "derived/growth", "derived/shrink"]

    assert Enum.all?(acked, &(&1.severity == :info and &1.severity_source == :ack))

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

    assert finding =
             Enum.find(report.all_findings, fn finding ->
               finding.code == "tags/tag_borrowed" and
                 finding.file == "test/sample_test.exs" and
                 finding.requirement == "sample.subject.works" and finding.severity == :info
             end)

    assert finding.message =~ "test/sample_test.exs"
    assert finding.message =~ "sample.subject.works"
  end

  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  @tag spec: "ancora.gate.diff_scoped_versus_repo_state"
  test "a second tag in the same file is the only borrowed tag", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() in [:current, :changed])

        @tag spec: "sample.subject.works"
        test "works twice", do: assert(Sample.value() in [:current, :changed])
      end
      """
    })

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    assert [%{file: "test/sample_test.exs"}] =
             Enum.filter(report.all_findings, &(&1.code == "tags/tag_borrowed"))
  end

  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  @tag spec: "ancora.gate.statement_change_disclosed"
  @tag spec: "ancora.gate.diff_scoped_versus_repo_state"
  test "an empty diff emits neither disclosure", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    assert {:ok, report} = Gate.check(root, base: "HEAD")

    refute Enum.any?(report.all_findings, &(&1.code == "tags/tag_borrowed"))
    refute Enum.any?(report.all_findings, &(&1.code == "append/statement_changed"))
  end

  @tag spec: "ancora.gate.borrowed_tag_disclosed"
  @tag spec: "ancora.gate.statement_change_disclosed"
  test "a whitespace-only statement edit keeps a new tag borrowed", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => mix_file("[app: :sample]"),
      ".spec/specs/sample.spec.md" => subject_spec("The sample shall work."),
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
      ".spec/specs/sample.spec.md" => subject_spec("The sample  shall work."),
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
               finding.requirement == "sample.subject.works"
           end)

    refute Enum.any?(report.all_findings, &(&1.code == "append/statement_changed"))
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

    stderr =
      capture_io(:stderr, fn ->
        send(self(), {:report, Gate.check(root, base: "HEAD~1")})
      end)

    assert_received {:report, {:ok, report}}

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.severity == :info and
               finding.severity_source == :trailer
           end)

    assert report.fail == false
    refute stderr =~ "lost by a squash merge"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "an applied trailer below the tip warns before squash", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    write_files(root, %{"README.md" => "tip\n"})
    commit_all(root, "tip without trailer")

    stderr =
      capture_io(:stderr, fn ->
        send(self(), {:report, Gate.check(root, base: "HEAD~2")})
      end)

    assert_received {:report, {:ok, report}}
    assert report.fail == false
    assert stderr =~ "Spec-Ack: derived/drift=info"
    assert stderr =~ "non-tip commit"
    assert stderr =~ "lost by a squash merge"
    assert stderr =~ ".spec/config.yml"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "a non-tip trailer that resolves no finding does not warn", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "unrelated ack\n\nSpec-Ack: derived/growth=info")
    write_files(root, %{"README.md" => "tip\n"})
    commit_all(root, "tip without trailer")

    stderr =
      capture_io(:stderr, fn ->
        send(self(), {:report, Gate.check(root, base: "HEAD~2")})
      end)

    assert_received {:report, {:ok, report}}
    assert report.fail == true
    refute stderr =~ "lost by a squash merge"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  test "a Spec-Ack trailer never raises a configured info finding", %{root: root} do
    init_git_repo(root)
    write_anchored_subject(root, "The sample shall return the current value.")
    write_config(root, "severities:\n  derived/drift: info\n")
    commit_all(root, "base")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=warning")

    assert {:ok, report} = Gate.check(root, base: "HEAD~1")

    assert Enum.any?(report.all_findings, fn finding ->
             finding.code == "derived/drift" and finding.severity == :info and
               finding.severity_source == :config
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

  defp collect_git_reads(objects) do
    receive do
      {:forwarded_trace, {:trace, _pid, :call, {Git, :read_blob, [_ctx, object]}}} ->
        collect_git_reads([object | objects])
    after
      0 -> Enum.reverse(objects)
    end
  end

  defp collect_ets_calls(calls) do
    receive do
      {:forwarded_trace, {:trace, _pid, :call, {:ets, fun, args}}} ->
        collect_ets_calls([{fun, args} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  defp count_source_parses(source, count) do
    receive do
      {:forwarded_trace, {:trace, _pid, :call, {Code, :string_to_quoted, [^source, _options]}}} ->
        count_source_parses(source, count + 1)

      {:forwarded_trace, _message} ->
        count_source_parses(source, count)
    after
      0 -> count
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
