defmodule Ancora.Parser do
  @moduledoc """
  Parses `.spec/specs/*.spec.md` files.

  `parse_file/2` is a semver-stable public function. Its return shape is a
  map with string keys `"file"`, `"title"`, `"meta"`, `"requirements"`,
  `"scenarios"`, `"verification"`, `"exceptions"`, `"parse_errors"`, and
  `"findings"`. That shape is unchanged within a major version.

  README documentation of this commitment lands at publish (L12); the
  commitment is recorded here.
  """

  alias Ancora.Finding
  alias Ancora.Schema
  alias Ancora.Schema.Verification

  @block_pattern ~r/```([^\n`]*)\n(.*?)\n```/ms
  @spec_tags ~w(spec-meta spec-requirements spec-scenarios spec-verification spec-exceptions)
  @seen_blocks_key "__seen_blocks__"

  @doc """
  Parses a spec file at `path` relative to `root`.

  This function is semver-stable public API.
  """
  @spec parse_file(Path.t(), Path.t()) :: map()
  def parse_file(path, root) do
    content = File.read!(path)

    @block_pattern
    |> Regex.scan(content)
    |> Enum.reduce(base_spec(path, root, content), fn [_, info_string, raw], spec ->
      case find_spec_tag(info_string) do
        nil -> spec
        tag -> decode_block(spec, tag, raw)
      end
    end)
    |> Map.delete(@seen_blocks_key)
    |> attach_findings()
  end

  defp find_spec_tag(info_string) do
    info_string
    |> String.split(~r/\s+/, trim: true)
    |> Enum.find(&(&1 in @spec_tags))
  end

  defp base_spec(path, root, content) do
    %{
      "file" => Path.relative_to(path, root),
      "title" => extract_title(content),
      "meta" => nil,
      "requirements" => [],
      "scenarios" => [],
      "verification" => [],
      "exceptions" => [],
      "parse_errors" => [],
      "findings" => [],
      @seen_blocks_key => MapSet.new()
    }
  end

  defp extract_title(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content, capture: :all_but_first) do
      [title] -> String.trim(title)
      _ -> nil
    end
  end

  defp decode_block(spec, "spec-meta", raw) do
    if seen_block?(spec, "spec-meta") do
      push_parse_error(spec, "spec-meta may only appear once per file")
    else
      spec = mark_block_seen(spec, "spec-meta")

      case decode_yaml(raw) do
        {:ok, meta} when is_map(meta) ->
          case Schema.validate_block("spec-meta", meta) do
            {:ok, validated} ->
              Map.put(spec, "meta", validated)

            {:error, message} ->
              push_parse_error(
                Map.put(spec, "meta", meta),
                contextualize(message, spec)
              )
          end

        {:ok, _invalid_shape} ->
          push_parse_error(spec, "spec-meta must decode to a mapping")

        {:error, message} ->
          push_parse_error(spec, "spec-meta decode failed: #{message}")
      end
    end
  end

  defp decode_block(spec, tag, raw) do
    key =
      case tag do
        "spec-requirements" -> "requirements"
        "spec-scenarios" -> "scenarios"
        "spec-verification" -> "verification"
        "spec-exceptions" -> "exceptions"
      end

    if seen_block?(spec, tag) do
      push_parse_error(spec, "#{tag} may only appear once per file")
    else
      spec = mark_block_seen(spec, tag)

      case decode_yaml(raw) do
        {:ok, items} when is_list(items) ->
          case Schema.validate_block(tag, items) do
            {:ok, validated} ->
              Map.put(spec, key, validated)

            {:error, message} ->
              push_parse_error(Map.put(spec, key, items), contextualize(message, spec))
          end

        {:ok, _invalid_shape} ->
          push_parse_error(spec, "#{tag} must decode to a list")

        {:error, message} ->
          push_parse_error(spec, "#{tag} decode failed: #{message}")
      end
    end
  end

  defp attach_findings(spec) do
    spec
    |> maybe_retired_construct_finding()
    |> parse_error_findings()
  end

  defp maybe_retired_construct_finding(spec) do
    details = retired_construct_details(spec)

    if details == [] do
      spec
    else
      push_finding(
        spec,
        finding(spec, "format/retired_construct", Enum.join(details, ", "))
      )
    end
  end

  defp parse_error_findings(spec) do
    Enum.reduce(spec["parse_errors"] || [], spec, fn message, acc ->
      push_finding(acc, finding(acc, "spec/parse_error", message))
    end)
  end

  defp retired_construct_details(spec) do
    []
    |> maybe_realized_by("realized_by: (spec-meta)", spec["meta"])
    |> add_requirement_realized_by(spec["requirements"] || [])
    |> add_verification_retired(spec["verification"] || [])
    |> add_scenario_execute(spec["scenarios"] || [])
    |> Enum.reverse()
  end

  defp maybe_realized_by(details, label, item) do
    if present?(field(item, "realized_by")) do
      [label | details]
    else
      details
    end
  end

  defp add_requirement_realized_by(details, requirements) do
    Enum.reduce(requirements, details, fn req, acc ->
      id = field(req, "id") || "requirement"
      maybe_realized_by(acc, "realized_by: (#{id})", req)
    end)
  end

  defp add_verification_retired(details, verifications) do
    verifications
    |> Enum.with_index()
    |> Enum.reduce(details, fn {entry, idx}, acc ->
      kind = field(entry, "kind")
      execute? = present?(field(entry, "execute"))
      kind_retired? = is_binary(kind) and Verification.retired_kind?(kind)

      cond do
        kind_retired? and execute? ->
          ["kind: #{kind} and execute: (verification[#{idx}])" | acc]

        kind_retired? ->
          ["kind: #{kind} (verification[#{idx}])" | acc]

        execute? ->
          ["execute: (verification[#{idx}])" | acc]

        true ->
          acc
      end
    end)
  end

  defp add_scenario_execute(details, scenarios) do
    Enum.reduce(scenarios, details, fn scenario, acc ->
      if present?(field(scenario, "execute")) do
        id = field(scenario, "id") || "scenario"
        ["execute: (#{id})" | acc]
      else
        acc
      end
    end)
  end

  defp finding(spec, code, detail) do
    Finding.new(
      code: code,
      file: spec["file"],
      subject: subject_id(spec),
      detail: detail,
      severity: Finding.default_severity(code),
      severity_source: :default
    )
  end

  defp subject_id(spec) do
    case field(spec["meta"], "id") do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp field(nil, _key), do: nil

  defp field(map, key) when is_map(map) and is_binary(key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    Map.get(map, key, if(atom_key, do: Map.get(map, atom_key)))
  end

  defp field(_map, _key), do: nil

  defp present?(nil), do: false
  defp present?(_value), do: true

  defp contextualize(message, %{"file" => file}) when is_binary(file),
    do: "#{message} (in #{file})"

  defp contextualize(message, _), do: message

  defp decode_yaml(raw) do
    case YamlElixir.read_from_string(raw) do
      {:ok, result} -> {:ok, result}
      {:error, %YamlElixir.ParsingError{message: message}} -> {:error, message}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp push_parse_error(spec, message) do
    Map.update!(spec, "parse_errors", &[message | &1])
  end

  defp push_finding(spec, finding) do
    Map.update(spec, "findings", [finding], &[finding | &1])
  end

  defp seen_block?(spec, tag) do
    spec
    |> Map.get(@seen_blocks_key, MapSet.new())
    |> MapSet.member?(tag)
  end

  defp mark_block_seen(spec, tag) do
    Map.update(spec, @seen_blocks_key, MapSet.new([tag]), &MapSet.put(&1, tag))
  end
end
