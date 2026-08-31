defmodule Mix.Tasks.Spec.Decision.New do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Scaffolds an ancora decision"
  @id_pattern ~r/\A[a-z0-9][a-z0-9._-]*\z/

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [root: :string, title: :string, force: :boolean],
        aliases: [r: :root, f: :force]
      )

    decision_id = validate_args!(rest, invalid)
    validate_id!(decision_id)

    root = opts[:root] || File.cwd!()
    path = Path.join([root, ".spec", "decisions", "#{decision_id}.md"])

    if File.exists?(path) and not (opts[:force] || false) do
      Mix.raise("Decision already exists: #{path}")
    end

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(decision_id, opts[:title] || humanize(decision_id)))
    Ancora.Output.puts("spec.decision.new wrote #{path}")
  end

  defp validate_args!([decision_id], []), do: decision_id

  defp validate_args!(rest, invalid) do
    invalid_flags = Enum.map(invalid, fn {flag, _value} -> flag end)
    extra_args = Enum.drop(rest, 1) |> Enum.map(&inspect/1)
    details = Enum.join(invalid_flags ++ extra_args, ", ")

    if details == "" do
      Mix.raise("spec.decision.new requires exactly one DECISION_ID argument")
    else
      Mix.raise("Invalid arguments for spec.decision.new: #{details}")
    end
  end

  defp validate_id!(decision_id) do
    unless Regex.match?(@id_pattern, decision_id) do
      Mix.raise("Invalid DECISION_ID: #{decision_id}")
    end
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
