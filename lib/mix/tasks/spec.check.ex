defmodule Mix.Tasks.Spec.Check do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Checks specs against the current git diff"
  @moduledoc """
  Checks the target corpus and source-derived bindings against a git base.

  A cold checkout may print dependency compilation lines before ancora output.

  #{Ancora.Output.read_protocol()}
  """

  alias Ancora.Output
  alias Ancora.TaskArgs

  @switches [
    base: :string,
    verbose: :boolean,
    debug: :boolean,
    root: :string,
    spec_dir: :string,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.check", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.check", rest, invalid) do
        :ok -> Ancora.check(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
