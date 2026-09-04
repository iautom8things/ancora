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
    * `--spec-dir DIR` selects the ancora workspace directory. Defaults to `.spec`.
  """

  alias Ancora.Output
  alias Ancora.TaskArgs

  @switches [strict: :boolean, debug: :boolean, root: :string, spec_dir: :string]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.validate", fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.validate", rest, invalid) do
        :ok -> validate(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end

  defp validate(root, opts) do
    with {:ok, spec_dir} <- spec_dir(root, opts),
         {:ok, _authored_dir} <- Ancora.Index.detect_authored_dir(root, spec_dir) do
      Ancora.validate(root, opts)
    else
      {:error, message} -> {:env, message}
    end
  end

  defp spec_dir(root, opts) do
    case Keyword.fetch(opts, :spec_dir) do
      {:ok, spec_dir} -> {:ok, spec_dir}
      :error -> Ancora.Index.detect_spec_dir(root)
    end
  end
end
