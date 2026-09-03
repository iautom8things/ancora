defmodule Mix.Tasks.Spec.Next do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Reports the next current-truth action"
  @moduledoc """
  Classifies the current git change set and prints one suggested check command.

  A cold checkout may print dependency compilation lines before ancora output.
  """

  alias Ancora.Next
  alias Ancora.Output
  alias Ancora.TaskArgs

  @switches [base: :string, since: :string, verbose: :boolean]

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
