Code.require_file("runner.exs", __DIR__)
Code.require_file("selection.exs", __DIR__)

defmodule AncoraReplay.CLI do
  @moduledoc false

  alias AncoraReplay.Result
  alias AncoraReplay.Runner
  alias AncoraReplay.Selection

  @spec main([String.t()]) :: 0 | 1 | 2
  def main(args) do
    args = if List.first(args) == "--", do: tl(args), else: args

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [selection: :string, atlas_repo: :string, builder_repo: :string, only: :string]
      )

    if rest != [] or invalid != [] do
      IO.puts(:stderr, "invalid arguments")
      2
    else
      run(opts)
    end
  rescue
    exception ->
      IO.puts(:stderr, "replay harness error: #{Exception.message(exception)}")
      2
  end

  defp run(opts) do
    selection = opts[:selection] || Path.join(__DIR__, "selection.tsv")
    cases = Selection.load!(selection) |> select(opts[:only])
    repos = %{"atlas" => opts[:atlas_repo], "builder" => opts[:builder_repo]}
    ancora_root = Path.expand("../..", __DIR__)

    evaluations =
      Enum.map(cases, fn replay_case ->
        case Map.get(repos, replay_case.repo) do
          nil -> {:error, "#{replay_case.name}: missing --#{replay_case.repo}-repo"}
          repo -> Runner.run(ancora_root, Path.expand(repo), replay_case)
        end
      end)

    Enum.each(evaluations, fn {_state, message} -> IO.puts(message) end)
    Result.exit_code(evaluations)
  end

  defp select(cases, nil), do: cases

  defp select(cases, name) do
    case Enum.filter(cases, &(&1.name == name)) do
      [] -> raise "selection has no case named #{name}"
      selected -> selected
    end
  end
end

System.halt(AncoraReplay.CLI.main(System.argv()))
