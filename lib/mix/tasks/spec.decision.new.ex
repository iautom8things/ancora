defmodule Mix.Tasks.Spec.Decision.New do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Scaffolds an ancora decision"
  @id_pattern ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @moduledoc """
  Scaffolds one decision record from a required `DECISION_ID` argument.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--root DIR`, `-r DIR` selects the target project. Defaults to the current directory.
    * `--title TEXT` sets the heading. Defaults to the humanized decision id.
    * `--force`, `-f` replaces an existing decision. Defaults to false.
  """

  @impl Mix.Task
  def run(args) do
    Ancora.Output.gated("spec.decision.new", fn ->
      {opts, rest, invalid} =
        OptionParser.parse(args,
          strict: [root: :string, title: :string, force: :boolean],
          aliases: [r: :root, f: :force]
        )

      with {:ok, decision_id} <- validate_args(rest, invalid),
           :ok <- validate_id(decision_id),
           root = opts[:root] || File.cwd!(),
           path = Path.join([root, ".spec", "decisions", "#{decision_id}.md"]),
           :ok <- available(path, opts[:force] || false) do
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, render(decision_id, opts[:title] || humanize(decision_id)))
        {:ok, %{lines: ["spec.decision.new wrote #{path}"]}}
      else
        {:error, message} -> {:usage, message}
      end
    end)
  end

  defp validate_args([decision_id], []), do: {:ok, decision_id}

  defp validate_args(rest, invalid) do
    invalid_flags = Enum.map(invalid, fn {flag, _value} -> flag end)
    extra_args = Enum.drop(rest, 1) |> Enum.map(&inspect/1)
    details = Enum.join(invalid_flags ++ extra_args, ", ")

    if details == "" do
      {:error, "spec.decision.new requires exactly one DECISION_ID argument"}
    else
      {:error, "Invalid arguments for spec.decision.new: #{details}"}
    end
  end

  defp validate_id(decision_id),
    do:
      if(Regex.match?(@id_pattern, decision_id),
        do: :ok,
        else: {:error, "Invalid DECISION_ID: #{decision_id}"}
      )

  defp available(path, force?) do
    if File.exists?(path) and not force?,
      do: {:error, "Decision already exists: #{path}"},
      else: :ok
  end

  defp render(decision_id, title) do
    """
    ---
    id: #{decision_id}
    status: proposed
    date: #{Date.utc_today()}
    affects: []
    ---

    # #{title}

    ## Context

    What needs a durable decision?

    ## Decision

    What did we decide?

    ## Consequences

    What follows from this decision?
    """
  end

  defp humanize(value) do
    value
    |> String.replace(~r/[._-]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
