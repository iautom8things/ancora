defmodule Ancora.ChangeAnalysis do
  @moduledoc """
  Diff-scoped findings for uncovered source, governance changes, and new requirements.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.Finding
  alias Ancora.PolicyFiles

  @spec findings(ChangeSet.t(), map(), map(), map(), %{head: map(), base: map()}) :: [Finding.t()]
  def findings(%ChangeSet{} = change_set, footprints, prior, current, tag_maps)
      when is_map(footprints) and is_map(prior) and is_map(current) and is_map(tag_maps) do
    paths = ChangeSet.paths(change_set)
    head_tags = Map.fetch!(tag_maps, :head)
    base_tags = Map.fetch!(tag_maps, :base)

    uncovered_findings(paths, footprints) ++
      missing_decision_findings(paths, current) ++
      new_requirement_findings(prior, current, Map.keys(head_tags)) ++
      borrowed_tag_findings(prior, current, head_tags, base_tags)
  end

  defp uncovered_findings(paths, footprints) do
    {lib_paths, footprints} = Map.pop(footprints, :__lib_paths__, ["lib"])
    covered = footprints |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    paths
    |> Enum.filter(&under_lib_path?(&1, lib_paths))
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> Enum.map(&Finding.new(code: "change/uncovered_file", file: &1))
  end

  defp under_lib_path?(path, lib_paths) do
    Enum.any?(lib_paths, fn lib_path ->
      String.starts_with?(path, lib_path <> "/")
    end)
  end

  defp missing_decision_findings(paths, current) do
    if PolicyFiles.missing_decision?(paths) do
      paths
      |> Enum.filter(&PolicyFiles.governance?/1)
      |> Enum.reject(&governed_subject_spec?(&1, current))
      |> Enum.map(fn path ->
        Finding.new(
          code: "change/missing_decision",
          file: path,
          message: missing_decision_message(path)
        )
      end)
    else
      []
    end
  end

  defp missing_decision_message(".spec/specs/" <> _rest = path) do
    "governance file #{path} changed without a decision update; " <>
      "reference a governing ADR from the spec's decisions: frontmatter with " <>
      "affects: naming the subject back, or add or update an ADR in the same diff"
  end

  defp missing_decision_message(path) do
    "governance file #{path} changed without a decision update; " <>
      "add or update an ADR in the same diff"
  end

  defp governed_subject_spec?(path, current) do
    with subject when is_map(subject) <- Enum.find(subjects(current), &(&1["file"] == path)),
         subject_id when is_binary(subject_id) <- field(subject["meta"], :id),
         decision_ids when is_list(decision_ids) <- field(subject["meta"], :decisions) do
      governed_ids =
        [subject_id | child_ids(subject, "requirements") ++ child_ids(subject, "scenarios")]
        |> MapSet.new()

      current
      |> Map.get("decisions", [])
      |> Enum.any?(&governs?(&1, decision_ids, governed_ids))
    else
      _ -> false
    end
  end

  defp governs?(decision, decision_ids, governed_ids) do
    meta = Map.get(decision, "meta")
    decision_id = field(meta, "id")
    affects = field(meta, "affects")

    decision_id in decision_ids and is_list(affects) and
      Enum.any?(affects, &MapSet.member?(governed_ids, &1))
  end

  defp child_ids(subject, key) do
    subject
    |> Map.get(key, [])
    |> Enum.map(&field(&1, :id))
    |> Enum.filter(&is_binary/1)
  end

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp field(_map, _key), do: nil

  defp new_requirement_findings(prior, current, tagged_ids) do
    prior_ids = requirement_ids(prior)
    tagged_ids = MapSet.new(tagged_ids)

    current
    |> subjects()
    |> Enum.flat_map(fn subject ->
      subject_id = subject |> Map.get("meta") |> Map.get(:id)
      file = subject["file"]

      subject
      |> Map.get("requirements", [])
      |> Enum.flat_map(fn requirement ->
        id = Map.get(requirement, :id)

        if is_binary(id) and not MapSet.member?(prior_ids, id) and
             not MapSet.member?(tagged_ids, id) do
          [
            Finding.new(
              code: "tags/new_requirement_untagged",
              subject: subject_id,
              file: file,
              requirement: id
            )
          ]
        else
          []
        end
      end)
    end)
  end

  defp requirement_ids(index) do
    index
    |> subjects()
    |> Enum.flat_map(&Map.get(&1, "requirements", []))
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp borrowed_tag_findings(prior, current, head_tags, base_tags) do
    prior_requirements = requirements_by_id(prior)
    current_requirements = requirements_by_id(current)

    Enum.flat_map(head_tags, fn {id, head_entries} ->
      with {:ok, prior_requirement} <- Map.fetch(prior_requirements, id),
           {:ok, current_requirement} <- Map.fetch(current_requirements, id),
           true <- prior_requirement.statement == current_requirement.statement do
        base_entries = base_tags |> Map.get(id, []) |> MapSet.new(&tag_identity/1)

        head_entries
        |> Enum.reject(&MapSet.member?(base_entries, tag_identity(&1)))
        |> Enum.map(fn entry ->
          Finding.new(code: "tags/tag_borrowed", file: entry.file, requirement: id)
        end)
      else
        _ -> []
      end
    end)
  end

  defp requirements_by_id(index) do
    index
    |> subjects()
    |> Enum.flat_map(fn subject ->
      subject
      |> Map.get("requirements", [])
      |> Enum.map(fn requirement ->
        {Map.get(requirement, :id),
         %{statement: normalize_statement(Map.get(requirement, :statement))}}
      end)
    end)
    |> Map.new()
  end

  defp normalize_statement(statement) when is_binary(statement) do
    statement
    |> String.split()
    |> Enum.join(" ")
  end

  defp normalize_statement(_statement), do: ""

  defp tag_identity(entry), do: {entry.file, entry.test_name}

  defp subjects(index), do: Map.get(index, "subjects", [])
end
