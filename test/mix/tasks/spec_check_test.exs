Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.CheckTest do
  use Ancora.TestCase

  @moduletag :tmp_dir

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

  if match?({"0\n", 0}, System.cmd("id", ["-u"])) do
    @tag skip: "chmod 000 does not deny reads when running as root"
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "unreadable working-tree inputs emit an environment verdict", %{root: root} do
    create_project(root)
    write_anchored_subject(root)
    commit_all(root, "anchored subject")

    for relative <- ["test/sample_test.exs", "lib/sample.ex"] do
      path = Path.join(root, relative)
      on_exit(fn -> File.chmod(path, 0o644) end)
      File.chmod!(path, 0o000)

      result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

      assert result.status == 1
      assert result.stdout =~ relative

      assert List.last(lines(result.stdout)) ==
               "spec.check result=fail tier=env errors=0 warnings=0"

      refute result.stderr =~ "RuntimeError"
      File.chmod!(path, 0o644)
    end
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
  test "internal exception has no verdict on stdout", %{root: root} do
    create_project(root)
    File.rm!(Path.join(root, ".spec/specs/.keep"))
    File.rmdir!(Path.join(root, ".spec/specs"))

    result = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
    assert result.status != 0
    refute result.stdout =~ "result="
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
    check = &Mix.Tasks.Spec.Check.run/1
    validate = &Mix.Tasks.Spec.Validate.run/1
    assert is_function(check, 1)
    assert is_function(validate, 1)
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
