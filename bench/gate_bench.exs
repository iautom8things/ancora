# AR10 re-entry blueprint: commit a generated corpus and a scripted mutation as
# two git states. The mutation touches about 10% of test files, 5% of lib files
# including watched function bodies, and one spec file. Assert the mutated run's
# findings, and calibrate the generator against the measured Atlas file sizes,
# alias/import density, nested describes, and macro DSL usage before setting a
# CI wall-clock limit.
#
# Operator descope, 2026-09-01: replay and benchmark gates run under Ancora's
# own toolchain. spec.check reads the target checkout's files and git history;
# it does not compile the target or need the target's .tool-versions.
#
# ETS note: public-table reads copy terms into the caller heap, so a future
# memory benchmark must count copied DefIndex/resolver terms, not table bytes.

defmodule AncoraBench.Gate do
  @moduledoc false

  @atlas_commit "4f6c0760f64ee3b04c70f9bc7a73589580b584be"
  @atlas_base "4f6c0760f64ee3b04c70f9bc7a73589580b584be^"

  @spec main([String.t()]) :: :ok
  def main(args) do
    args = if List.first(args) == "--", do: tl(args), else: args

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [atlas: :string, commit: :string, base: :string]
      )

    if rest != [] or invalid != [] or is_nil(opts[:atlas]) do
      raise "usage: mix run bench/gate_bench.exs -- --atlas PATH [--commit SHA] [--base REF]"
    end

    atlas = Path.expand(opts[:atlas])
    commit = opts[:commit] || @atlas_commit
    base = opts[:base] || @atlas_base
    assert_pinned!(atlas, commit)

    times = Enum.map(1..3, fn run -> timed_gate!(atlas, base, run) end)
    median = times |> Enum.sort() |> Enum.at(1)

    IO.puts("atlas_commit=#{commit} base=#{base}")
    IO.puts("runs_ms=#{Enum.map_join(times, ",", &format_ms/1)}")
    IO.puts("median_ms=#{format_ms(median)}")
  end

  defp assert_pinned!(atlas, commit) do
    {head, 0} = System.cmd("git", ["-C", atlas, "rev-parse", "HEAD"], stderr_to_stdout: true)

    unless String.trim(head) == commit do
      raise "Atlas checkout HEAD is #{String.trim(head)}, expected pinned commit #{commit}"
    end
  end

  defp timed_gate!(atlas, base, run) do
    started = System.monotonic_time()

    {_stdout, status} =
      System.cmd(
        "mix",
        ["spec.check", "--root", atlas, "--base", base],
        cd: Path.expand("..", __DIR__),
        env: [{"MIX_ENV", "dev"}]
      )

    elapsed = System.monotonic_time() - started

    unless status in [0, 1] do
      raise "gate run #{run} exited #{status}"
    end

    System.convert_time_unit(elapsed, :native, :microsecond) / 1_000
  end

  defp format_ms(milliseconds), do: :erlang.float_to_binary(milliseconds, decimals: 1)
end

AncoraBench.Gate.main(System.argv())
