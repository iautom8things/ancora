defmodule Mix.Tasks.Spec.Next do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Reports the next current-truth action"
  @moduledoc """
  Classifies the current git change set and prints one suggested check command.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--base REF` selects the git base. Defaults to configured `default_base`.
    * `--since REF` selects the starting revision and overrides `--base`. Defaults to unset.
    * `--verbose` lists changed and policy files. Defaults to false.
    * `--spec-dir DIR` selects the ancora workspace directory. Defaults to `.spec`.
  """

  alias Ancora.Next
  alias Ancora.Output
  alias Ancora.TaskArgs

  @switches [base: :string, since: :string, verbose: :boolean, spec_dir: :string]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.next", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.next", rest, invalid) do
        :ok -> Next.build(File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
