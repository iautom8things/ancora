defmodule Mix.Tasks.Spec.Prime do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Prints session-start status and guidance"
  @moduledoc """
  Prints status, current-change guidance, and the default local loop.

  A cold checkout may print dependency compilation lines before ancora output.
  """

  alias Ancora.Output
  alias Ancora.Prime
  alias Ancora.TaskArgs

  @switches [base: :string, since: :string, root: :string, spec_dir: :string]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.prime", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.prime", rest, invalid) do
        :ok -> Prime.build(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
