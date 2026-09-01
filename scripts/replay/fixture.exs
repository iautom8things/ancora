defmodule AncoraReplay.Fixture do
  @moduledoc false

  @base_source """
  defmodule ReplayFixture.Calculator do
    def add(left, right), do: left+right
  end
  """

  @formatted_source """
  defmodule ReplayFixture.Calculator do
    def add(left, right), do: left + right
  end
  """

  @drift_source """
  defmodule ReplayFixture.Calculator do
    def add(left, right), do: left - right
  end
  """

  @spec_source """
  # Fixture calculator

  Synthetic contract used only by the replay harness self-test.

  ```spec-meta
  id: replay.fixture
  kind: module
  status: active
  summary: Adds two numbers.
  surface:
    - lib/replay_fixture/calculator.ex
  ```

  ## Requirements

  ```spec-requirements
  - id: replay.fixture.add
    statement: The calculator shall add two numbers.
    priority: must
    stability: stable
  ```

  ## Scenarios

  ```spec-scenarios
  - id: replay.fixture.scenario.add
    given:
      - two integers
    when:
      - ReplayFixture.Calculator.add/2 is called
    then:
      - their sum is returned
    covers:
      - replay.fixture.add
  ```

  ## Verification

  ```spec-verification
  - kind: tagged_tests
    target: test/replay_fixture/calculator_test.exs
    covers:
      - replay.fixture.add
  ```
  """

  @test_source """
  defmodule ReplayFixture.CalculatorTest do
    use ExUnit.Case

    @tag spec: "replay.fixture.add"
    test "adds two numbers" do
      assert ReplayFixture.Calculator.add(1, 2) == 3
    end
  end
  """

  @spec build!() :: %{root: Path.t(), base: String.t(), drift: String.t(), format: String.t()}
  def build! do
    root = fresh_dir!()
    git!(root, ["init", "-b", "main"])
    git!(root, ["config", "user.name", "Ancora Replay"])
    git!(root, ["config", "user.email", "replay@example.com"])
    git!(root, ["config", "commit.gpgsign", "false"])
    git!(root, ["config", "core.hooksPath", "/dev/null"])

    write_new!(root, ".tool-versions", "erlang 27.2\nelixir 1.18.1-otp-27\n")
    write_new!(root, "mix.exs", mix_source())
    write_new!(root, ".spec/config.yml", minimal_config())
    write_new!(root, ".spec/specs/replay.fixture.spec.md", @spec_source)
    write_new!(root, "lib/replay_fixture/calculator.ex", @base_source)
    write_new!(root, "test/replay_fixture/calculator_test.exs", @test_source)
    commit!(root, "fixture base")
    base = git!(root, ["rev-parse", "HEAD"])

    replace!(root, "lib/replay_fixture/calculator.ex", @drift_source)
    commit!(root, "change calculator interface body")
    drift = git!(root, ["rev-parse", "HEAD"])

    git!(root, ["checkout", "-B", "format-control", base])
    replace!(root, "lib/replay_fixture/calculator.ex", @formatted_source)
    commit!(root, "mix format")
    format = git!(root, ["rev-parse", "HEAD"])

    %{root: root, base: base, drift: drift, format: format}
  end

  defp fresh_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "ancora-replay-fixture-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    :ok = File.mkdir(path)
    path
  end

  defp write_new!(root, relative, contents) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    {:ok, file} = File.open(path, [:write, :exclusive])
    :ok = IO.binwrite(file, contents)
    :ok = File.close(file)
    assert_file!(path, contents)
  end

  defp replace!(root, relative, contents) do
    path = Path.join(root, relative)
    temp = path <> ".replace-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, file} = File.open(temp, [:write, :exclusive])
    :ok = IO.binwrite(file, contents)
    :ok = File.close(file)
    assert_file!(temp, contents)
    :ok = File.rename(temp, path)
    assert_file!(path, contents)
  end

  defp assert_file!(path, contents) do
    unless File.regular?(path) and File.read!(path) == contents and contents != "" do
      raise "write postcondition failed for #{path}"
    end
  end

  defp commit!(root, message) do
    git!(root, ["add", "-A"])
    git!(root, ["commit", "--no-verify", "-m", message])
  end

  defp git!(root, args) do
    case System.cmd("git", ["-C", root | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  defp mix_source do
    """
    defmodule ReplayFixture.MixProject do
      use Mix.Project

      def project do
        [app: :replay_fixture, version: "0.1.0", elixir: "~> 1.18"]
      end
    end
    """
  end

  defp minimal_config do
    """
    test_paths:
      - test
    lib_paths:
      - lib
    severities:
      change/missing_decision: off
    """
  end
end
