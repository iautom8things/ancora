defmodule Ancora.DecisionParser do
  @moduledoc """
  Parses `.spec/decisions/*.md` ADR files.

  `parse_file/2` is a semver-stable public function. Its return shape is a
  map with string keys `"file"`, `"title"`, `"meta"`, `"sections"`,
  `"parse_errors"`, `"parse_warnings"`, and `"findings"`. That shape is
  unchanged within a major version.

  Frontmatter fields `change_type`, `supersedes`, `replaces`, and
  `reverses_what` are parsed and ignored: they produce no finding.
  README documentation of this commitment lands at publish (L12); the
  commitment is recorded here.
  """

  alias Ancora.DecisionParser.Affects
  alias Ancora.Finding

  @frontmatter_pattern ~r/\A---\s*\n(.*?)\n---\s*(?:\n|$)(.*)\z/ms
  @required_sections ~w(Context Decision Consequences)

  @doc """
  Parses a single ADR file.

  This function is semver-stable public API.
  """
  @spec parse_file(Path.t(), Path.t()) :: map()
  def parse_file(path, root) do
    parse_file(path, root, nil, [])
  end

  @doc false
  @spec parse_file(Path.t(), Path.t(), map() | nil, keyword()) :: map()
  def parse_file(path, root, current_index, opts) do
    content = File.read!(path)

    decision =
      case Regex.run(@frontmatter_pattern, content, capture: :all_but_first) do
        [raw_meta, body] ->
          base_decision(path, root, content)
          |> decode_meta(raw_meta)
          |> Map.put("sections", extract_sections(body))

        _ ->
          base_decision(path, root, content)
          |> push_parse_error("decision frontmatter missing")
          |> Map.put("sections", extract_sections(content))
      end

    decision
    |> attach_section_findings()
    |> attach_parse_error_findings()
    |> maybe_run_affects(current_index, opts)
  end

  @doc false
  def required_sections, do: @required_sections

  @doc false
  def validate_affects(decisions, current_index, opts \\ []) when is_list(decisions) do
    Enum.map(decisions, fn decision ->
      maybe_run_affects(decision, current_index, opts)
    end)
  end

  defp maybe_run_affects(decision, nil, _opts), do: decision

  defp maybe_run_affects(decision, current_index, _opts) do
    decision
    |> Affects.validate(current_index)
    |> Enum.reduce(decision, &route_affects/2)
  end

  defp route_affects(%{code: code, message: message} = diagnostic, decision) do
    finding =
      Finding.new(
        code: code,
        file: decision["file"],
        subject: diagnostic[:decision_id],
        detail: diagnostic[:detail] || message,
        severity: Finding.default_severity(code),
        severity_source: :default
      )

    push_finding(decision, finding)
  end

  defp base_decision(path, root, content) do
    %{
      "file" => Path.relative_to(path, root),
      "title" => extract_title(content),
      "meta" => nil,
      "sections" => [],
      "parse_errors" => [],
      "parse_warnings" => [],
      "findings" => []
    }
  end

  defp decode_meta(decision, raw) do
    case decode_yaml(raw) do
      {:ok, meta} when is_map(meta) ->
        Map.put(decision, "meta", meta)

      {:ok, _invalid_shape} ->
        push_parse_error(decision, "decision frontmatter must decode to a mapping")

      {:error, message} ->
        push_parse_error(decision, "decision frontmatter decode failed: #{message}")
    end
  end

  defp attach_section_findings(decision) do
    sections = decision["sections"] || []

    Enum.reduce(@required_sections, decision, fn section, acc ->
      if section in sections do
        acc
      else
        push_finding(
          acc,
          Finding.new(
            code: "adr/missing_section",
            file: acc["file"],
            subject: decision_id(acc),
            detail: section,
            severity: Finding.default_severity("adr/missing_section"),
            severity_source: :default
          )
        )
      end
    end)
  end

  defp attach_parse_error_findings(decision) do
    Enum.reduce(decision["parse_errors"] || [], decision, fn message, acc ->
      push_finding(
        acc,
        Finding.new(
          code: "adr/parse_error",
          file: acc["file"],
          subject: decision_id(acc),
          detail: message,
          severity: Finding.default_severity("adr/parse_error"),
          severity_source: :default
        )
      )
    end)
  end

  defp extract_sections(content) do
    ~r/^##\s+(.+)$/m
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [heading] -> String.trim(heading) end)
  end

  defp extract_title(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content, capture: :all_but_first) do
      [title] -> String.trim(title)
      _ -> nil
    end
  end

  defp decode_yaml(raw) do
    case YamlElixir.read_from_string(raw) do
      {:ok, result} -> {:ok, result}
      {:error, %YamlElixir.ParsingError{message: message}} -> {:error, message}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decision_id(%{"meta" => meta}) when is_map(meta) do
    case Map.get(meta, "id") do
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  defp decision_id(_), do: nil

  defp push_parse_error(decision, message) do
    Map.update(decision, "parse_errors", [message], &[message | &1])
  end

  defp push_finding(decision, finding) do
    Map.update(decision, "findings", [finding], &[finding | &1])
  end
end
