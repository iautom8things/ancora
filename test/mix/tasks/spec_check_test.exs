Code.require_file("../../support/ancora_case.exs", __DIR__)
Code.require_file("../../support/tmp_git_repo.exs", __DIR__)

defmodule Mix.Tasks.Spec.CheckTest do
  use Ancora.TestCase

  alias Ancora.TmpGitRepo

  @squash_warning "[CONFIG] Spec-Ack: derived/drift=info resolved from a non-tip commit and will be lost by a squash merge; promote it to .spec/config.yml before merging\n"

  @tag spec: "ancora.tasks.gated_emission_paths"
  @tag spec: "ancora.tasks.verdict_grammar"
  @tag spec: "ancora.tasks.exit_codes"
  test "green subprocess keeps the verdict last on stdout", %{root: root} do
    create_project(root)
    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

    assert result.status == 0
    assert List.last(lines(result.stdout)) == "spec.check result=pass"
    refute result.stderr =~ "result="
  end

  @tag spec: "ancora.tasks.gated_emission_paths"
  @tag spec: "ancora.tasks.check_flags"
  test "usage and environment failures emit their verdict last", %{root: root} do
    create_project(root)

    usage = run_mix_subprocess(["spec.check", "--root", root, "--no-run-commands"])
    assert usage.status == 1
    assert List.last(lines(usage.stdout)) =~ "result=fail tier=usage"

    env = run_mix_subprocess(["spec.check", "--root", root])
    assert env.status == 1
    assert env.stdout =~ "git fetch origin main"
    assert List.last(lines(env.stdout)) =~ "result=fail tier=env"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  @tag spec: "ancora.tasks.gated_emission_paths"
  test "a missing corpus emits an environment verdict and init remedy", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """
    })

    commit_all(root, "base")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

    assert result.status == 1
    assert result.stdout =~ "no .spec/ directory"
    assert result.stdout =~ "mix spec.init"

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=env errors=0 warnings=0"

    refute result.stderr =~ "RuntimeError"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "an incomplete shallow range fails before trailer resolution", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :middle_one\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    ack_commit = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :middle_two\nend\n"
    })

    commit_all(root, "change value again")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value at head")

    full = run_mix_subprocess(["spec.check", "--root", root, "--base", base])
    assert full.status == 0
    assert List.last(lines(full.stdout)) == "spec.check result=pass"

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    assert git!(root, ["show", "-s", "--format=%B", ack_commit]) =~
             "Spec-Ack: derived/drift=info"

    {_output, status} =
      System.cmd("git", ["-C", shallow, "cat-file", "-e", "#{ack_commit}^{commit}"],
        stderr_to_stdout: true
      )

    assert status != 0

    result = run_mix_subprocess(["spec.check", "--root", shallow, "--base", base, "--json"])

    assert result.status == 1
    assert last_parseable_json(result.stdout)["all_findings"] == []
    assert result.stdout =~ "base..HEAD history is incomplete"
    assert result.stdout =~ "git fetch --unshallow"
    assert result.stdout =~ "fetch-depth: 0"

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=env errors=0 warnings=0"
  end

  @tag spec: "ancora.findings.info_visibility"
  test "an incomplete shallow range JSON report has no findings", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :middle_one\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    ack_commit = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :middle_two\nend\n"
    })

    commit_all(root, "change value again")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value at head")

    shallow = TmpGitRepo.shallow_clone!(root)
    on_exit(fn -> TmpGitRepo.cleanup!(shallow) end)
    TmpGitRepo.git!(shallow, ["fetch", "--depth=1", "origin", base])

    {_output, status} =
      System.cmd("git", ["-C", shallow, "cat-file", "-e", "#{ack_commit}^{commit}"],
        stderr_to_stdout: true
      )

    assert status != 0

    result = run_mix_subprocess(["spec.check", "--root", shallow, "--base", base, "--json"])

    assert result.status == 1
    assert last_parseable_json(result.stdout)["all_findings"] == []

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=env errors=0 warnings=0"
  end

  if match?({"0\n", 0}, System.cmd("id", ["-u"])) do
    @tag skip: "chmod 000 does not deny reads when running as root"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "an unreadable test emits an environment verdict", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    assert_unreadable_input(root, "test/sample_test.exs")
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "an unreadable library source emits an environment verdict", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    assert_unreadable_input(root, "lib/sample.ex")
  end

  @tag spec: "ancora.tasks.gated_emission_paths"
  @tag spec: "ancora.tasks.finding_line_format"
  test "findings precede summaries, guidance, and the last-line verdict", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    output_lines = lines(result.stdout)

    assert result.status == 1
    assert Enum.at(output_lines, 0) =~ "derived/drift"
    assert Enum.any?(output_lines, &String.starts_with?(&1, "checked subjects="))
    assert Enum.any?(output_lines, &String.starts_with?(&1, "branch base="))
    assert Enum.any?(output_lines, &String.starts_with?(&1, "branch next="))
    assert List.last(output_lines) =~ "spec.check result=fail tier=branch errors=1"
  end

  @tag spec: "ancora.tasks.gated_emission_paths"
  test "a requested subject directory is an environment failure", %{root: root} do
    create_project(root)

    result =
      run_mix_subprocess([
        "spec.check",
        "--root",
        root,
        "--base",
        "HEAD",
        "--spec-dir",
        ".spec/specs"
      ])

    assert result.status == 1
    assert result.stdout =~ "--spec-dir selects the ancora workspace directory"
    assert result.stdout =~ ".spec/specs/specs directory not found"

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=env errors=0 warnings=0"

    refute result.stderr =~ "** (RuntimeError)"
  end

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.check_flags"
  test "tasks read a corpus from a non-default workspace", %{root: root} do
    create_custom_spec_project(root)

    invocations = [
      {["spec.check", "--root", root, "--base", "HEAD", "--spec-dir", "docs/spec"],
       "checked subjects=1"},
      {["spec.validate", "--root", root, "--spec-dir", "docs/spec"], "checked subjects=1"},
      {["spec.status", "--root", root, "--spec-dir", "docs/spec"], "subjects=1"},
      {[
         "spec.prime",
         "--root",
         root,
         "--base",
         "HEAD",
         "--spec-dir",
         "docs/spec"
       ], "Spec Led Prime"},
      {[
         "spec.review",
         "--root",
         root,
         "--base",
         "HEAD",
         "--spec-dir",
         "docs/spec"
       ], "spec.review wrote"}
    ]

    for {args, expected} <- invocations do
      result = run_mix_subprocess(args)
      assert result.status == 0, result.stdout <> result.stderr
      assert result.stdout =~ expected
      refute result.stderr =~ "** ("
    end
  end

  @tag spec: "ancora.tasks.check_flags"
  test "json mode includes a growth finding before the last-line verdict", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")

    write_files(root, %{
      "lib/sample.ex" => """
      defmodule Sample do
        def value, do: :current
        def other, do: :new
      end
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works" do
          assert Sample.value() == :current
          assert Sample.other() == :new
        end
      end
      """
    })

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD", "--json"])

    assert result.status == 1
    output_lines = lines(result.stdout)
    assert List.last(output_lines) =~ "spec.check result=fail tier=branch"

    report = last_parseable_json(result.stdout)
    assert Enum.any?(report["findings"], &(&1["code"] == "derived/growth"))
  end

  @tag spec: "ancora.tasks.json_report"
  test "json ok, environment, usage, and branch paths share one versioned shape", %{root: root} do
    # Would fail if a CLI consumer had to select keys based on the failure path.
    create_project(root)

    ok = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD", "--json"])
    env = run_mix_subprocess(["spec.check", "--root", root, "--json"])

    usage =
      run_mix_subprocess([
        "spec.check",
        "--root",
        root,
        "--json",
        "--no-run-commands"
      ])

    write_anchored_subject(root)
    commit_all(root, "anchored subject")

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    branch =
      run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD", "--json"])

    results = [ok, env, usage, branch]
    reports = Enum.map(results, &last_parseable_json(&1.stdout))

    assert Enum.map(results, & &1.status) == [0, 1, 1, 1]
    assert Enum.all?(reports, &(&1["version"] == 1))

    expected_keys =
      MapSet.new(
        ~w(all_findings branch checked errors fail findings guidance message tier version warnings)
      )

    assert Enum.all?(reports, &(MapSet.new(Map.keys(&1)) == expected_keys))
    assert reports |> Enum.map(&Map.keys(&1["checked"])) |> Enum.uniq() |> length() == 1
    assert reports |> Enum.map(&Map.keys(&1["branch"])) |> Enum.uniq() |> length() == 1
    assert reports |> Enum.map(&Map.keys(&1["guidance"])) |> Enum.uniq() |> length() == 1
    assert Enum.at(reports, 0)["message"] == nil
    assert Enum.at(reports, 1)["message"] =~ "cannot be resolved"
    assert Enum.at(reports, 2)["message"] =~ "--no-run-commands"
    assert Enum.at(reports, 3)["message"] == nil

    for result <- results do
      assert List.last(lines(result.stdout)) =~ ~r/^spec\.check result=/
    end
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "json mode reports a target-read error without plain stdout leakage", %{root: root} do
    # Would fail if a preflight target error took the text-only fail path and
    # left JSON consumers without a report.
    create_project(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: app_name()]
      end
      """
    })

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD", "--json"])

    assert result.status == 1
    assert [_json, verdict] = lines(result.stdout)
    report = last_parseable_json(result.stdout)
    assert report["all_findings"] == []
    assert report["message"] =~ "app: as a literal atom"
    assert verdict == "spec.check result=fail tier=env errors=0 warnings=0"
  end

  test "subprocess capture silences Mix diagnostics without silencing direct stdout" do
    result =
      run_mix_subprocess([
        "run",
        "-e",
        ~s|Mix.shell().info("Waiting for lock on the build directory"); IO.puts(~s({"ok":true}))|
      ])

    assert result.status == 0
    assert lines(result.stdout) == [~s|{"ok":true}|]
  end

  @tag spec: "ancora.tasks.check_flags"
  test "every retired check flag is a usage error", %{root: root} do
    create_project(root)

    for flag_args <- [
          ["--min-strength", "1"],
          ["--command-timeout-ms", "1"],
          ["--accept-drift"],
          ["--test-tags", "1"],
          ["--no-run-commands"]
        ] do
      result = run_mix_subprocess(["spec.check", "--root", root] ++ flag_args)
      assert result.status == 1
      assert List.last(lines(result.stdout)) =~ "spec.check result=fail tier=usage"
    end
  end

  @tag spec: "ancora.tasks.check_flags"
  @tag spec: "ancora.tasks.validate_flags"
  test "gate task callable surfaces are present" do
    Code.ensure_loaded!(Mix.Tasks.Spec.Check)
    Code.ensure_loaded!(Mix.Tasks.Spec.Validate)
    assert function_exported?(Mix.Tasks.Spec.Check, :run, 1)
    assert function_exported?(Mix.Tasks.Spec.Validate, :run, 1)
  end

  @tag spec: "ancora.tasks.stderr_pinning"
  test "config diagnostics stay on stderr and verdict stays last", %{root: root} do
    create_project(root)
    write_config(root, "not: [valid")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    assert result.status == 1
    assert result.stderr =~ "[CONFIG]"
    refute result.stdout =~ "[CONFIG]"
    assert List.last(lines(result.stdout)) =~ "spec.check result=fail tier=branch"
  end

  @tag spec: "ancora.findings.per_subject_overrides"
  test "an unknown override key is reported and the override is not applied", %{root: root} do
    create_project(root)
    write_unanchored_subject(root)

    write_config(root, """
    overrides:
      - subject: sample.subject
        requirement: sample.subject.works
        code: derived/unanchored_subject
        severity: info
        reason: integration-only
    """)

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD", "--json"])
    report = last_parseable_json(result.stdout)

    assert result.status == 1

    assert Enum.any?(report["findings"], fn finding ->
             finding["code"] == "config/unknown_key" and
               finding["message"] =~ ~s("requirement") and
               finding["message"] =~ "sample.subject"
           end)

    assert Enum.any?(report["findings"], fn finding ->
             finding["code"] == "derived/unanchored_subject" and
               finding["subject"] == "sample.subject" and
               finding["severity"] == "warning"
           end)

    assert List.last(lines(result.stdout)) =~ "spec.check result=fail tier=branch"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "the tip acknowledgment wins when commits name conflicting severities", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    write_files(root, %{"notes.md" => "The tip narrows the acknowledgment.\n"})
    commit_all(root, "narrow acknowledgment\n\nSpec-Ack: derived/drift=warning")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    report = last_parseable_json(result.stdout)
    drift = Enum.find(report["all_findings"], &(&1["code"] == "derived/drift"))

    assert result.status == 1
    assert drift["severity"] == "warning"
    assert drift["severity_source"] == "trailer"

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=branch errors=0 warnings=1"

    assert result.stderr == "** (Mix) spec.check failed\n"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "a non-tip acknowledgment changes the result after squash", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    git!(root, ["checkout", "-b", "feature"])

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    write_files(root, %{"notes.md" => "The tip has no acknowledgment.\n"})
    commit_all(root, "document branch state")

    branch = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    branch_report = last_parseable_json(branch.stdout)
    branch_drift = Enum.find(branch_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert branch.status == 0
    assert branch_drift["severity"] == "info"
    assert branch_drift["severity_source"] == "trailer"
    assert List.last(lines(branch.stdout)) == "spec.check result=pass"
    assert branch.stderr == @squash_warning

    git!(root, ["checkout", "main"])
    git!(root, ["merge", "--squash", "feature"])
    commit_all(root, "squash feature without trailer")

    trunk = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    trunk_report = last_parseable_json(trunk.stdout)
    trunk_drift = Enum.find(trunk_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert trunk.status == 1
    assert trunk_drift["severity"] == "error"
    assert trunk_drift["severity_source"] == "default"

    assert List.last(lines(trunk.stdout)) ==
             "spec.check result=fail tier=branch errors=1 warnings=0"

    assert trunk.stderr == "** (Mix) spec.check failed\n"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "the nearest below-tip acknowledgment warns before squash", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    git!(root, ["checkout", "-b", "feature"])

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=warning")
    write_files(root, %{"older.md" => "The nearer acknowledgment lowers the severity.\n"})
    commit_all(root, "lower severity\n\nSpec-Ack: derived/drift=info")
    write_files(root, %{"tip.md" => "The tip has no acknowledgment.\n"})
    commit_all(root, "document branch tip")

    branch = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    branch_report = last_parseable_json(branch.stdout)
    branch_drift = Enum.find(branch_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert branch.status == 0
    assert branch_drift["severity"] == "info"
    assert branch_drift["severity_source"] == "trailer"
    assert List.last(lines(branch.stdout)) == "spec.check result=pass"
    assert branch.stderr == @squash_warning

    git!(root, ["checkout", "main"])
    git!(root, ["merge", "--squash", "feature"])
    commit_all(root, "squash feature without trailer")

    trunk = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    trunk_report = last_parseable_json(trunk.stdout)
    trunk_drift = Enum.find(trunk_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert trunk.status == 1
    assert trunk_drift["severity"] == "error"
    assert trunk_drift["severity_source"] == "default"

    assert List.last(lines(trunk.stdout)) ==
             "spec.check result=fail tier=branch errors=1 warnings=0"

    assert trunk.stderr == "** (Mix) spec.check failed\n"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "a non-tunable finding does not get squash promotion advice", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    write_config(root, "severities:\n  config/unknown_key: info\nbogus_top_level_key: true\n")
    commit_all(root, "anchored subject with invalid config")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{"branch.md" => "The branch carries an invalid acknowledgment.\n"})
    commit_all(root, "acknowledge non-tunable finding\n\nSpec-Ack: config/unknown_key=warning")
    write_files(root, %{"tip.md" => "The tip has no acknowledgment.\n"})
    commit_all(root, "document branch tip")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])

    assert result.status == 1
    assert result.stderr == "** (Mix) spec.check failed\n"
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "repeating the non-tip acknowledgment on the tip stays silent", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")
    write_files(root, %{"notes.md" => "The tip repeats the acknowledgment.\n"})
    commit_all(root, "repeat acknowledgment\n\nSpec-Ack: derived/drift=info")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    report = last_parseable_json(result.stdout)
    drift = Enum.find(report["all_findings"], &(&1["code"] == "derived/drift"))

    assert result.status == 0
    assert drift["severity"] == "info"
    assert drift["severity_source"] == "trailer"
    assert result.stderr == ""
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "promoted acknowledgment survives a squash merge", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()
    git!(root, ["checkout", "-b", "feature"])

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")

    write_files(root, %{"notes.md" => "Keep the branch acknowledgment until it is promoted.\n"})
    commit_all(root, "document branch state")

    unpromoted = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    unpromoted_report = last_parseable_json(unpromoted.stdout)

    unpromoted_drift =
      Enum.find(unpromoted_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert unpromoted.status == 0
    assert unpromoted_drift["severity"] == "info"
    assert unpromoted_drift["severity_source"] == "trailer"
    assert unpromoted.stderr == @squash_warning

    write_config(root, "severities:\n  derived/drift: info\n")

    write_decision(root, "promote-ack", """
    ---
    id: sample.decision.promote_ack
    status: accepted
    date: 2026-09-03
    affects:
      - sample.subject
    ---

    # Promote the acknowledgment

    ## Context

    The branch carries a temporary trailer.

    ## Decision

    Record the severity in config before merging.

    ## Consequences

    The acknowledgment survives a squash merge.
    """)

    commit_all(root, "promote acknowledgment")

    promoted = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    promoted_report = last_parseable_json(promoted.stdout)
    promoted_drift = Enum.find(promoted_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert promoted.status == 0
    assert promoted_drift["severity"] == "info"
    assert promoted_drift["severity_source"] == "trailer"
    assert promoted.stderr == ""

    git!(root, ["checkout", "main"])
    git!(root, ["merge", "--squash", "feature"])
    commit_all(root, "squash feature without trailer")

    trunk = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    trunk_report = last_parseable_json(trunk.stdout)
    trunk_drift = Enum.find(trunk_report["all_findings"], &(&1["code"] == "derived/drift"))

    assert trunk.status == 0
    assert trunk_drift["severity"] == promoted_drift["severity"]
    assert trunk_drift["severity_source"] == "config"
    assert trunk.stderr == ""
  end

  @tag spec: "ancora.gate.acknowledgment_clears"
  @tag spec: "ancora.tasks.stderr_pinning"
  test "non-tip trailer warns when config would restore a higher severity", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")
    base = root |> git!(["rev-parse", "HEAD"]) |> String.trim()

    write_files(root, %{
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :changed\nend\n"
    })

    commit_all(root, "change value\n\nSpec-Ack: derived/drift=info")

    write_config(root, "severities:\n  derived/drift: warning\n")

    write_decision(root, "retain-stricter-severity", """
    ---
    id: sample.decision.retain_stricter_severity
    status: accepted
    date: 2026-09-03
    affects:
      - sample.subject
    ---

    # Retain the stricter severity

    ## Context

    The branch trailer is temporary.

    ## Decision

    Keep drift at warning after the trailer is removed.

    ## Consequences

    Losing the trailer changes the branch verdict.
    """)

    write_files(root, %{"notes.md" => "The configured severity remains stricter.\n"})
    commit_all(root, "configure stricter severity")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", base, "--json"])
    report = last_parseable_json(result.stdout)
    drift = Enum.find(report["all_findings"], &(&1["code"] == "derived/drift"))

    assert result.status == 0
    assert drift["severity"] == "info"
    assert drift["severity_source"] == "trailer"
    assert result.stderr == @squash_warning
  end

  @tag spec: "ancora.gate.strict_verdict"
  @tag spec: "ancora.tasks.exit_codes"
  test "a warning-only corpus fails spec.check", %{root: root} do
    create_project(root)
    write_unanchored_subject(root)
    commit_all(root, "unanchored subject")

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

    assert result.status == 1
    assert result.stdout =~ "derived/unanchored_subject"

    assert List.last(lines(result.stdout)) =~
             "spec.check result=fail tier=branch errors=0 warnings=1"
  end

  @tag spec: "ancora.tasks.check_flags"
  @tag spec: "ancora.gate.no_derived_state"
  test "output flag is rejected and writes no file", %{root: root} do
    create_project(root)
    output = Path.join(root, "x.json")
    result = run_mix_subprocess(["spec.check", "--root", root, "--output", output])

    assert result.status == 1
    assert List.last(lines(result.stdout)) =~ "result=fail tier=usage"
    refute File.exists?(output)
  end

  @tag spec: "ancora.tasks.mix_bootstrap_posture"
  test "target compile errors are never compiled", %{root: root} do
    create_project(root)

    write_files(root, %{
      "lib/not_compilable.ex" => "defmodule Nope do\n  raise \"compiled target\"\nend\n"
    })

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    assert result.status != 0
    refute result.stderr =~ "compiled target"
    assert List.last(lines(result.stdout)) =~ "spec.check result=fail tier="
  end

  defp create_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")
  end

  defp create_custom_spec_project(root) do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/.keep" => "",
      "docs/spec/specs/sample.spec.md" => """
      # Sample

      ```yaml spec-meta
      id: sample.subject
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: sample.subject.works
        statement: The sample shall work.
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
      """,
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :ok\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(Sample.value() == :ok)
      end
      """
    })

    commit_all(root, "base")
  end

  defp write_anchored_subject(root) do
    write_files(root, %{
      ".spec/specs/sample.spec.md" => """
      # Sample

      ```yaml spec-meta
      id: sample.subject
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: sample.subject.works
        statement: The sample shall return its value.
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
      """,
      "lib/sample.ex" => "defmodule Sample do\n  def value, do: :current\nend\n",
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works" do
          assert Sample.value() in [:current, :changed]
          assert apply(Sample, :value, []) in [:current, :changed]
        end
      end
      """
    })
  end

  defp write_unanchored_subject(root) do
    write_files(root, %{
      ".spec/specs/sample.spec.md" => """
      # Sample

      ```yaml spec-meta
      id: sample.subject
      kind: module
      status: draft
      ```

      ```yaml spec-requirements
      - id: sample.subject.works
        statement: The sample shall work.
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
      """,
      "test/sample_test.exs" => """
      defmodule SampleTest do
        use ExUnit.Case
        @tag spec: "sample.subject.works"
        test "works", do: assert(true)
      end
      """
    })
  end

  defp lines(output), do: String.split(output, "\n", trim: true)

  defp assert_unreadable_input(root, relative) do
    path = Path.join(root, relative)
    on_exit(fn -> File.chmod(path, 0o644) end)
    File.chmod!(path, 0o000)

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

    assert result.status == 1
    assert result.stdout =~ relative
    assert result.stdout =~ to_string(:file.format_error(:eacces))

    assert List.last(lines(result.stdout)) ==
             "spec.check result=fail tier=env errors=0 warnings=0"

    refute result.stderr =~ "RuntimeError"
  end

  defp last_parseable_json(output) do
    output
    |> lines()
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, value} -> value
        {:error, _error} -> nil
      end
    end)
  end
end
