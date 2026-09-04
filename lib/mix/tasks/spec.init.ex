defmodule Mix.Tasks.Spec.Init do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Scaffolds an ancora workspace"
  @moduledoc """
  Scaffolds an ancora workspace without replacing existing files by default.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--root DIR`, `-r DIR` selects the target project. Defaults to the current directory.
    * `--force`, `-f` replaces existing scaffold files. Defaults to false.
  """

  @impl Mix.Task
  def run(args) do
    Ancora.Output.gated("spec.init", fn ->
      {opts, rest, invalid} =
        OptionParser.parse(args,
          strict: [root: :string, force: :boolean],
          aliases: [r: :root, f: :force]
        )

      case Ancora.TaskArgs.validate("spec.init", rest, invalid) do
        :ok ->
          result = Ancora.Init.scaffold(opts[:root] || File.cwd!(), force: opts[:force] || false)

          lines =
            Enum.map(result.files, fn file ->
              "#{file.status} #{file.path}"
            end)

          {:ok, %{lines: lines ++ ["spec.init scaffolded #{result.directory}"]}}

        {:error, message} ->
          {:usage, message}
      end
    end)
  end
end
