defmodule Ancora.OutputTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ancora.Finding
  alias Ancora.Output

  setup do
    on_exit(&restore_logger_stdio/0)
    :ok
  end

  defp restore_logger_stdio do
    case :logger.get_handler_config(:default) do
      {:ok, %{config: %{type: :standard_io}}} ->
        :ok

      {:ok, handler} ->
        _ = :logger.remove_handler(:default)

        :logger.add_handler(:default, handler.module, %{
          level: handler.level,
          filters: handler.filters,
          filter_default: handler.filter_default,
          formatter: handler.formatter,
          config: Map.put(handler.config, :type, :standard_io)
        })

      {:error, _} ->
        :ok
    end
  end

  defp finding(attrs) do
    Finding.new(
      Keyword.merge(
        [code: "derived/drift", subject: "ancora.tasks", file: "lib/ancora/output.ex"],
        attrs
      )
    )
  end

  defp stdout_of(fun) do
    capture_io(fun)
  end

  defp last_line(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> List.last()
  end

  describe "read_protocol/0" do
    @tag spec: "ancora.tasks.read_protocol_constant"
    test "returns the designed sentence verbatim" do
      assert Output.read_protocol() ==
               "The verdict is the last stdout line: `spec.check result=…`. A non-zero exit with no verdict line means the run crashed before the gate finished — treat it as failure."
    end
  end

  describe "gated/2" do
    @tag spec: "ancora.tasks.gated_emission_paths"
    test "ok pass renders the checked summary and a pass verdict" do
      report = %{
        checked: %{subjects: 2, requirements: 4, errors: 0, warnings: 0}
      }

      stdout =
        stdout_of(fn ->
          assert :ok = Output.gated("spec.check", fn -> {:ok, report} end)
        end)

      lines = String.split(stdout, "\n", trim: true)
      assert "checked subjects=2 requirements=4 errors=0 warnings=0" in lines
      assert List.last(lines) == "spec.check result=pass"
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "ok with blocking findings emits fail and raises" do
      report = %{
        findings: [finding(severity: :error)],
        checked: %{subjects: 1, requirements: 1, errors: 1, warnings: 0},
        tier: :branch
      }

      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, fn ->
            Output.gated("spec.check", fn -> {:ok, report} end)
          end
        end)

      assert last_line(stdout) == "spec.check result=fail tier=branch errors=1 warnings=0"
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "usage prints the message, a usage verdict, and raises" do
      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, "--no-run-commands is not accepted", fn ->
            Output.gated("spec.check", fn -> {:usage, "--no-run-commands is not accepted"} end)
          end
        end)

      lines = String.split(stdout, "\n", trim: true)
      assert "--no-run-commands is not accepted" in lines
      assert List.last(lines) == "spec.check result=fail tier=usage errors=0 warnings=0"
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "env prints the remedy on stdout before the env verdict" do
      remedy =
        "unresolvable base origin/main; pass --base HEAD, set default_base, or add the remote"

      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, remedy, fn ->
            Output.gated("spec.check", fn -> {:env, remedy} end)
          end
        end)

      lines = String.split(stdout, "\n", trim: true)
      assert remedy in lines
      assert List.last(lines) == "spec.check result=fail tier=env errors=0 warnings=0"
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "internal re-raises with no verdict line" do
      stdout =
        stdout_of(fn ->
          assert_raise RuntimeError, "boom", fn ->
            Output.gated("spec.check", fn -> raise "boom" end)
          end
        end)

      refute stdout =~ "result="
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "internal tuple from fun re-raises with no verdict line" do
      stdout =
        stdout_of(fn ->
          assert_raise RuntimeError, "stage 4 exploded", fn ->
            Output.gated("spec.check", fn ->
              {:internal, %RuntimeError{message: "stage 4 exploded"}}
            end)
          end
        end)

      refute stdout =~ "result="
    end

    @tag spec: "ancora.tasks.gated_emission_paths"
    test "report-task usage prints the message and raises without a verdict" do
      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, "--json is not accepted", fn ->
            Output.gated("spec.prime", fn -> {:usage, "--json is not accepted"} end)
          end
        end)

      assert stdout =~ "--json is not accepted"
      refute stdout =~ "result="
    end

    @tag spec: "ancora.tasks.exit_codes"
    test "gate success returns :ok and gate failure raises Mix.Error" do
      stdout_of(fn ->
        assert :ok = Output.gated("spec.validate", fn -> {:ok, %{}} end)
      end)

      stdout_of(fn ->
        assert_raise Mix.Error, fn ->
          Output.gated("spec.validate", fn -> {:usage, "bad flag"} end)
        end
      end)
    end
  end

  describe "finding line format" do
    @tag spec: "ancora.tasks.finding_line_format"
    test "prints [SEV] subject code file :: message" do
      line =
        Output.finding_line(
          finding(
            code: "derived/growth",
            severity: :warning,
            subject: "ancora.tasks",
            file: "lib/ancora/output.ex",
            message: "tests now call new functions"
          )
        )

      assert line ==
               "[WARNING] ancora.tasks derived/growth lib/ancora/output.ex :: tests now call new functions"
    end

    @tag spec: "ancora.tasks.finding_line_format"
    test "sorts warnings, then info, then errors last" do
      findings = [
        finding(code: "derived/drift", severity: :error, message: "drift"),
        finding(code: "derived/unresolved_calls", severity: :info, message: "unresolved"),
        finding(code: "derived/growth", severity: :warning, message: "growth")
      ]

      assert Enum.map(Output.sort_findings(findings), & &1.severity) == [
               :warning,
               :info,
               :error
             ]
    end

    @tag spec: "ancora.tasks.finding_line_format"
    test "checked summary matches the designed line" do
      assert Output.checked_summary(%{subjects: 7, requirements: 16, errors: 1, warnings: 2}) ==
               "checked subjects=7 requirements=16 errors=1 warnings=2"
    end

    @tag spec: "ancora.tasks.finding_line_format"
    test "branch summary and guidance lines follow findings" do
      report = %{
        findings: [
          finding(severity: :warning, message: "growth"),
          finding(code: "derived/drift", severity: :error, message: "drift")
        ],
        checked: %{subjects: 1, requirements: 2, errors: 1, warnings: 1},
        branch: %{
          base: "origin/main",
          changed_files: 3,
          findings: 2,
          errors: 1,
          warnings: 1,
          info: 0
        },
        guidance: %{
          impacted_subjects: ["ancora.tasks"],
          next: "mix spec.check --base HEAD"
        },
        tier: :branch
      }

      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, fn ->
            Output.gated("spec.check", fn -> {:ok, report} end)
          end
        end)

      lines = String.split(stdout, "\n", trim: true)
      assert hd(lines) =~ ~r/^\[WARNING\] /
      assert Enum.at(lines, 1) =~ ~r/^\[ERROR\] /
      assert "checked subjects=1 requirements=2 errors=1 warnings=1" in lines

      assert "branch base=origin/main changed_files=3 findings=2 (error=1 warning=1 info=0, info hidden)" in lines

      assert "branch impacted_subjects=ancora.tasks" in lines
      assert "branch next=mix spec.check --base HEAD" in lines
      assert List.last(lines) == "spec.check result=fail tier=branch errors=1 warnings=1"
    end

    @tag spec: "ancora.tasks.finding_line_format"
    test "validate output has a checked summary and no validate status= line" do
      report = %{
        findings: [finding(code: "spec/parse_error", severity: :error, message: "bad yaml")],
        checked: %{subjects: 3, requirements: 8, errors: 1, warnings: 0},
        tier: :validate
      }

      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, fn ->
            Output.gated("spec.validate", fn -> {:ok, report} end)
          end
        end)

      lines = String.split(stdout, "\n", trim: true)
      refute Enum.any?(lines, &String.starts_with?(&1, "validate status="))
      assert "checked subjects=3 requirements=8 errors=1 warnings=0" in lines
      assert List.last(lines) == "spec.validate result=fail tier=validate errors=1 warnings=0"
    end
  end

  describe "stderr pinning" do
    @tag spec: "ancora.tasks.stderr_pinning"
    test "config diagnostic is on stderr and not on stdout" do
      {stdout, stderr} =
        with_stdio(fn ->
          Output.config_diagnostic("config.yml is not valid YAML; using defaults")
        end)

      assert stdout == ""
      assert stderr =~ "[CONFIG] config.yml is not valid YAML; using defaults"
      refute stderr =~ "result="
    end

    @tag spec: "ancora.tasks.stderr_pinning"
    test "gated stdout has no [CONFIG] line" do
      {stdout, stderr} =
        with_stdio(fn ->
          Output.config_diagnostic("malformed")
          Output.gated("spec.check", fn -> {:ok, %{}} end)
        end)

      refute stdout =~ "[CONFIG]"
      assert stderr =~ "[CONFIG] malformed"
      assert last_line(stdout) == "spec.check result=pass"
    end
  end

  describe "json" do
    @tag spec: "ancora.tasks.verdict_grammar"
    test "json payload precedes the verdict on stdout" do
      report = %{
        json: true,
        findings: [finding(severity: :warning, message: "growth")],
        tier: :branch
      }

      stdout =
        stdout_of(fn ->
          assert_raise Mix.Error, fn ->
            Output.gated("spec.check", fn -> {:ok, report} end)
          end
        end)

      lines = String.split(stdout, "\n", trim: true)
      json = Enum.join(Enum.drop(lines, -1), "\n")
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded["findings"])
      assert List.last(lines) == "spec.check result=fail tier=branch errors=0 warnings=1"
    end
  end

  defp with_stdio(fun) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> fun.() end)
        send(parent, {:stdout, stdout})
      end)

    receive do
      {:stdout, stdout} -> {stdout, stderr}
    after
      1000 -> flunk("did not capture stdout")
    end
  end
end

defmodule Ancora.Output.LoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  require Logger

  @moduletag spec: "ancora.tasks.stderr_pinning"

  setup do
    on_exit(&restore_logger_stdio/0)
    :ok
  end

  defp restore_logger_stdio do
    case :logger.get_handler_config(:default) do
      {:ok, %{config: %{type: :standard_io}}} ->
        :ok

      {:ok, handler} ->
        _ = :logger.remove_handler(:default)

        :logger.add_handler(:default, handler.module, %{
          level: handler.level,
          filters: handler.filters,
          filter_default: handler.filter_default,
          formatter: handler.formatter,
          config: Map.put(handler.config, :type, :standard_io)
        })

      {:error, _} ->
        :ok
    end
  end

  test "Logger output after gated/2 is on stderr, not stdout" do
    stdout =
      capture_io(fn ->
        Ancora.Output.gated("spec.check", fn ->
          Logger.warning("diag-noise")
          Logger.flush()
          {:ok, %{}}
        end)
      end)

    {:ok, %{config: config}} = :logger.get_handler_config(:default)
    assert config[:type] == :standard_error
    refute stdout =~ "diag-noise"
    assert String.split(stdout, "\n", trim: true) |> List.last() == "spec.check result=pass"
  end
end
