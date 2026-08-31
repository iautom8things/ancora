defmodule Mix.Tasks.Spec.Init do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Scaffolds an ancora workspace"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [root: :string, force: :boolean],
        aliases: [r: :root, f: :force]
      )

    Ancora.TaskArgs.validate!("spec.init", rest, invalid)

    result = Ancora.Init.scaffold(opts[:root] || File.cwd!(), force: opts[:force] || false)

    Enum.each(result.files, fn file ->
      Ancora.Output.puts("#{file.status} #{file.path}")
    end)

    Ancora.Output.puts("spec.init scaffolded #{result.directory}")
  end
end
