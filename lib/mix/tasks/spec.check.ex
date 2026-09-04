defmodule Mix.Tasks.Spec.Check do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Checks specs against the current git diff"
  @moduledoc """
  Checks the target corpus and source-derived bindings against a git base.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--base REF` selects the git base. Defaults to configured `default_base`.
    * `--verbose` includes info findings. Defaults to false.
    * `--debug` is an accepted no-op. Defaults to false.
    * `--root DIR` selects the target project. Defaults to the current directory.
    * `--spec-dir DIR` selects the ancora workspace directory. Defaults to `.spec`.
    * `--json` emits a versioned JSON report before the verdict. Defaults to false.
    * `--explain-acks` lists only findings whose severity_source is `:trailer` or `:ack`, independent of `--verbose` and `ANCORA_SHOW_INFO`. Defaults to false.

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
    json: :boolean,
    explain_acks: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Output.gated("spec.check", [json: "--json" in args], fn ->
      {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

      case TaskArgs.validate("spec.check", rest, invalid) do
        :ok -> Ancora.check(opts[:root] || File.cwd!(), opts)
        {:error, message} -> {:usage, message}
      end
    end)
  end
end
