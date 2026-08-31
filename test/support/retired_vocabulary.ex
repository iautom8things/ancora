defmodule Ancora.RetiredVocabulary do
  @moduledoc false

  @fixed [
    "execute:",
    "realized_by:",
    "--no-run-commands",
    "--accept-drift",
    "state.json",
    "realization_hashes.json",
    "Spec-Drift:",
    "SPECLED_"
  ]

  def needles(migration_path) do
    (@fixed ++ old_codes(migration_path))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def outside_code_map(contents) do
    contents
    |> String.split("## Finding code map", parts: 2)
    |> hd()
  end

  defp old_codes(path) do
    current = MapSet.new(Ancora.Finding.codes())

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.flat_map(&old_cell_tokens/1)
    |> Enum.reject(&MapSet.member?(current, &1))
  end

  defp old_cell_tokens(row) do
    case String.split(row, "|", trim: true) do
      [old, _current] ->
        ~r/`([^`]+)`/
        |> Regex.scan(old, capture: :all_but_first)
        |> List.flatten()

      _other ->
        []
    end
  end
end
