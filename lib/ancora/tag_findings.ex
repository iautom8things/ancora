defmodule Ancora.TagFindings do
  @moduledoc """
  Repo-state findings from a tag scan. Tags are always on: there is no
  enforcement toggle.

  Emits `tags/parse_error`, `tags/dynamic_value`, `tags/unknown_requirement`,
  and `tags/requirement_untagged`. `tags/new_requirement_untagged` is
  diff-scoped and is not produced here.
  """

  alias Ancora.Finding

  @doc """
  Builds tag findings from an index and a `TagScanner.scan/2` result.

  `tag_map` keys are the literal ids discovered in tests (not folded).
  Unknown-requirement uses those keys against the corpus; untagged uses
  every requirement id.
  """
  @spec findings(map(), %{String.t() => [map()]}, [map()], [map()]) :: [Finding.t()]
  def findings(index, tag_map, parse_errors \\ [], dynamics \\ [])
      when is_map(index) and is_map(tag_map) and is_list(parse_errors) and is_list(dynamics) do
    subjects = index["subjects"] || []
    corpus_ids = corpus_ids(index)
    tagged_ids = MapSet.new(Map.keys(tag_map))

    parse_error_findings(parse_errors) ++
      dynamic_value_findings(dynamics) ++
      unknown_requirement_findings(tag_map, corpus_ids) ++
      requirement_untagged_findings(subjects, tagged_ids)
  end

  defp parse_error_findings(entries) do
    Enum.map(entries, fn entry ->
      file = fetch(entry, "file")
      reason = fetch(entry, "reason")

      finding("tags/parse_error",
        file: file,
        detail: inspect(reason)
      )
    end)
  end

  defp dynamic_value_findings(entries) do
    Enum.map(entries, fn entry ->
      file = fetch(entry, "file")
      line = fetch(entry, "line") || 0

      finding("tags/dynamic_value",
        file: file,
        detail: "#{file}:#{line}"
      )
    end)
  end

  defp unknown_requirement_findings(tag_map, corpus_ids) do
    tag_map
    |> Enum.flat_map(fn {id, entries} ->
      if MapSet.member?(corpus_ids, id) do
        []
      else
        files =
          entries
          |> Enum.map(&fetch(&1, "file"))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        files =
          if files == [] do
            [nil]
          else
            files
          end

        Enum.map(files, fn file ->
          finding("tags/unknown_requirement",
            file: file,
            detail: id
          )
        end)
      end
    end)
  end

  defp requirement_untagged_findings(subjects, tagged_ids) do
    Enum.flat_map(subjects, fn subject ->
      subject_id = subject_id(subject)
      file = fetch(subject, "file")

      subject
      |> list_field("requirements")
      |> Enum.map(&id_of/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&MapSet.member?(tagged_ids, &1))
      |> Enum.map(fn req_id ->
        finding("tags/requirement_untagged",
          subject: subject_id,
          file: file,
          requirement: req_id
        )
      end)
    end)
  end

  defp corpus_ids(index) do
    subjects = index["subjects"] || []
    decisions = index["decisions"] || []

    subject_ids = Enum.map(subjects, &subject_id/1)
    requirement_ids = Enum.flat_map(subjects, &ids_in(&1, "requirements"))
    scenario_ids = Enum.flat_map(subjects, &ids_in(&1, "scenarios"))
    decision_ids = Enum.map(decisions, &decision_id/1)

    [subject_ids, requirement_ids, scenario_ids, decision_ids]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp ids_in(subject, key) do
    subject
    |> list_field(key)
    |> Enum.map(&id_of/1)
  end

  defp subject_id(subject) do
    case fetch(subject, "meta") do
      meta when is_map(meta) -> id_of(meta)
      _ -> id_of(subject)
    end
  end

  defp decision_id(decision) do
    case fetch(decision, "meta") do
      meta when is_map(meta) -> id_of(meta)
      _ -> nil
    end
  end

  defp id_of(item), do: fetch(item, "id")

  defp list_field(map, key) do
    case fetch(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp finding(code, attrs) do
    attrs = Map.new(attrs)

    Finding.new(%{
      code: code,
      subject: Map.get(attrs, :subject),
      file: Map.get(attrs, :file),
      requirement: Map.get(attrs, :requirement),
      detail: Map.get(attrs, :detail),
      severity: Finding.default_severity(code),
      severity_source: :default
    })
  end

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    Map.get(map, key, if(atom_key, do: Map.get(map, atom_key)))
  end

  defp fetch(_, _), do: nil
end
