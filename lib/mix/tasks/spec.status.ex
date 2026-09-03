defmodule Mix.Tasks.Spec.Status do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Reports source-derived corpus status"
  @moduledoc """
  Reports corpus counts and per-subject source-derived binding counts.

  A cold checkout may print dependency compilation lines before ancora output.
  Thin means fewer than three derived bindings. This threshold is fixed and
  cannot be configured. Corpus findings do not make this report task fail.

  ## Options

    * `--root DIR` selects the target project. Defaults to the current directory.
    * `--spec-dir DIR` selects the subject directory. Defaults to `.spec/specs`.
  """

  alias Ancora.Output
  alias Ancora.Status
  alias Ancora.TaskArgs

  @switches [root: :string, spec_dir: :string]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.status", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.status", rest, invalid) do
        :ok -> Status.build(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
