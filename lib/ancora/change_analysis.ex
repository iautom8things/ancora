defmodule Ancora.ChangeAnalysis do
  @moduledoc """
  Diff-scoped findings for uncovered source, governance changes, and new requirements.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.Finding
  alias Ancora.PolicyFiles

  @spec findings(ChangeSet.t(), map(), map(), map(), [String.t()]) :: [Finding.t()]
  def findings(%ChangeSet{} = change_set, footprints, prior, current, tagged_ids)
      when is_map(footprints) and is_map(prior) and is_map(current) and is_list(tagged_ids) do
    paths = ChangeSet.paths(change_set)

    uncovered_findings(paths, footprints) ++
      missing_decision_findings(paths) ++
      new_requirement_findings(prior, current, tagged_ids)
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
      prefix = String.trim_trailing(lib_path, "/")
      String.starts_with?(path, prefix <> "/")
    end)
  end

  defp missing_decision_findings(paths) do
    if PolicyFiles.missing_decision?(paths) do
      paths
      |> Enum.filter(&PolicyFiles.governance?/1)
      |> Enum.map(&Finding.new(code: "change/missing_decision", file: &1))
    else
      []
    end
  end

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

  defp subjects(index), do: Map.get(index, "subjects", [])
end
