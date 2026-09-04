defmodule Ancora.Index do
  @moduledoc false

  alias Ancora.DecisionParser
  alias Ancora.DecisionParser.Affects
  alias Ancora.Parser

  @atom_keys Map.new(
               ~w(
                 affects covers date decisions execute file given id kind meta polarity priority
                 realized_by reason refines replaces requirements retires reverses_what scenarios
                 stability statement status summary superseded_by supersedes surface target then
                 verification verification_minimum_strength when
               )a,
               &{Atom.to_string(&1), &1}
             )

  @doc false
  def field(nil, _key), do: nil

  def field(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case @atom_keys do
          %{^key => atom_key} -> Map.get(map, atom_key)
          %{} -> nil
        end
    end
  end

  def field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  def field(_value, _key), do: nil

  @doc false
  def subject_id(subject) when is_map(subject) do
    id = subject |> field("meta") |> field("id") || field(subject, "id")
    if is_binary(id) and id != "", do: id, else: nil
  end

  def subject_id(_subject), do: nil

  @doc """
  Builds the in-memory corpus index for `root`.

  Parses every `*.spec.md` under the authored specs directory and every
  ADR under the decisions directory. Does not scan test tags and does not
  take realization inputs.
  """
  @spec build(Path.t(), keyword()) :: map() | {:error, String.t()}
  def build(root, opts \\ []) do
    with {:ok, spec_dir} <- resolve_spec_dir(root, opts),
         {:ok, authored_dir} <- resolve_authored_dir(root, spec_dir, opts) do
      decision_dir = opts[:decision_dir] || detect_decision_dir(root, spec_dir)

      spec_files =
        authored_dir
        |> expand_path(root)
        |> Path.join("**/*.spec.md")
        |> Path.wildcard()
        |> Enum.sort()

      decision_files =
        if decision_dir && File.dir?(expand_path(decision_dir, root)) do
          decision_dir
          |> expand_path(root)
          |> Path.join("**/*.md")
          |> Path.wildcard()
          |> Enum.reject(&(Path.basename(&1) == "README.md"))
          |> Enum.sort()
        else
          []
        end

      subjects = Enum.map(spec_files, &Parser.parse_file(&1, root))
      decisions = Enum.map(decision_files, &DecisionParser.parse_file(&1, root))
      current_index = %{"subjects" => subjects, "decisions" => decisions}
      resolvable_ids = Affects.resolvable_ids(current_index)

      validated =
        DecisionParser.validate_affects(
          decisions,
          resolvable_ids,
          opts
        )

      %{
        "version" => 1,
        "generated_at" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "spec_dir" => spec_dir,
        "authored_dir" => authored_dir,
        "decision_dir" => decision_dir,
        "subjects" => subjects,
        "decisions" => validated,
        "findings" => collect_findings(subjects, validated),
        "summary" => summary(subjects, validated)
      }
    end
  end

  def detect_spec_dir(root) do
    if File.dir?(Path.join(root, ".spec")) do
      {:ok, ".spec"}
    else
      {:error, "no .spec/ directory in #{root}; run mix spec.init"}
    end
  end

  def detect_authored_dir(root, spec_dir) do
    authored = join_dir(spec_dir, "specs")

    if File.dir?(expand_path(authored, root)) do
      {:ok, authored}
    else
      {:error,
       "--spec-dir selects the ancora workspace directory; " <>
         "#{authored} directory not found in #{root}."}
    end
  end

  def detect_decision_dir(_root, spec_dir) do
    join_dir(spec_dir, "decisions")
  end

  defp resolve_spec_dir(root, opts) do
    case Keyword.fetch(opts, :spec_dir) do
      {:ok, spec_dir} -> {:ok, spec_dir}
      :error -> detect_spec_dir(root)
    end
  end

  defp resolve_authored_dir(root, spec_dir, opts) do
    case Keyword.fetch(opts, :authored_dir) do
      {:ok, authored_dir} -> {:ok, authored_dir}
      :error -> detect_authored_dir(root, spec_dir)
    end
  end

  defp collect_findings(subjects, decisions) do
    (Enum.flat_map(subjects, &(&1["findings"] || [])) ++
       Enum.flat_map(decisions, &(&1["findings"] || [])))
    |> Enum.reverse()
  end

  defp join_dir(dir, child) do
    if Path.type(dir) == :absolute do
      Path.join(dir, child)
    else
      "#{dir}/#{child}"
    end
  end

  defp expand_path(path, root) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(root, path)
    end
  end

  defp summary(subjects, decisions) do
    subject_summary =
      Enum.reduce(
        subjects,
        %{
          "subjects" => 0,
          "requirements" => 0,
          "scenarios" => 0,
          "verification_items" => 0,
          "exceptions" => 0,
          "parse_errors" => 0
        },
        fn subject, acc ->
          acc
          |> Map.update!("subjects", &(&1 + 1))
          |> Map.update!("requirements", &(&1 + length(subject["requirements"] || [])))
          |> Map.update!("scenarios", &(&1 + length(subject["scenarios"] || [])))
          |> Map.update!("verification_items", &(&1 + length(subject["verification"] || [])))
          |> Map.update!("exceptions", &(&1 + length(subject["exceptions"] || [])))
          |> Map.update!("parse_errors", &(&1 + length(subject["parse_errors"] || [])))
        end
      )

    Enum.reduce(
      decisions,
      Map.merge(subject_summary, %{
        "decisions" => 0,
        "decision_parse_errors" => 0,
        "decision_parse_warnings" => 0
      }),
      fn decision, acc ->
        acc
        |> Map.update!("decisions", &(&1 + 1))
        |> Map.update!("decision_parse_errors", &(&1 + length(decision["parse_errors"] || [])))
        |> Map.update!(
          "decision_parse_warnings",
          &(&1 + length(decision["parse_warnings"] || []))
        )
      end
    )
  end
end
