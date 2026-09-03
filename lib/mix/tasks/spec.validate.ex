defmodule Mix.Tasks.Spec.Validate do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Validates an ancora corpus"
  @moduledoc """
  Validates the target corpus without compiling the target project.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--strict` makes warnings fail validation. Defaults to false.
    * `--debug` is an accepted no-op. Defaults to false.
    * `--root DIR` selects the target project. Defaults to the current directory.
    * `--spec-dir DIR` selects the subject directory. Defaults to `.spec/specs`.
  """

  alias Ancora.Output
  alias Ancora.TaskArgs

  @switches [strict: :boolean, debug: :boolean, root: :string, spec_dir: :string]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.validate", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.validate", rest, invalid) do
        :ok -> Ancora.validate(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
