defmodule Ancora.Index do
  @moduledoc false

  alias Ancora.{DecisionParser, Parser}

  @doc """
  Builds the in-memory corpus index for `root`.

  Parses every `*.spec.md` under the authored specs directory and every
  ADR under the decisions directory. Does not scan test tags and does not
  take realization inputs.
  """
  def build(root, opts \\ []) do
    spec_dir = opts[:spec_dir] || detect_spec_dir(root)
    authored_dir = opts[:authored_dir] || detect_authored_dir(root, spec_dir)
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

    validated =
      DecisionParser.validate_affects(
        decisions,
        %{"subjects" => subjects, "decisions" => decisions},
        opts
      )

    %{
      "version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "spec_dir" => spec_dir,
      "authored_dir" => authored_dir,
      "decision_dir" => decision_dir,
      "subjects" => subjects,
      "decisions" => validated,
      "findings" => collect_findings(subjects, validated),
      "summary" => summary(subjects, validated)
    }
  end

  def detect_spec_dir(root) do
    if File.dir?(Path.join(root, ".spec")) do
      ".spec"
    else
      raise ".spec directory not found in #{root}."
    end
  end

  def detect_authored_dir(root, spec_dir) do
    authored = join_dir(spec_dir, "specs")

    if File.dir?(expand_path(authored, root)) do
      authored
    else
      raise "#{authored} directory not found in #{root}."
    end
  end

  def detect_decision_dir(_root, spec_dir) do
    join_dir(spec_dir, "decisions")
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
