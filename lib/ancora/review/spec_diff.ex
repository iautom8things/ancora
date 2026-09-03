defmodule Ancora.Review.SpecDiff do
  @moduledoc false

  alias Ancora.BaseView
  alias Ancora.Parser

  @spec compute(map(), map() | nil) :: map()
  def compute(head, base) when is_map(head) do
    %{
      file_changed?: head != base,
      base_existed?: not is_nil(base),
      requirements: changes(head["requirements"] || [], field(base, "requirements")),
      scenarios: changes(head["scenarios"] || [], field(base, "scenarios"))
    }
  end

  @spec compute(Path.t(), String.t(), map()) :: map()
  def compute(root, base_ref, head)
      when is_binary(root) and is_binary(base_ref) and is_map(head) do
    file = Map.get(head, "file")

    base =
      case BaseView.blobs(root, base_ref, pathspecs: [file]) do
        {:ok, %{^file => source}} -> parse_source(source)
        _ -> nil
      end

    compute(head, base)
  end

  defp parse_source(source) do
    root = Path.join(System.tmp_dir!(), "ancora_spec_diff_#{System.unique_integer([:positive])}")
    path = Path.join(root, "subject.spec.md")
    File.mkdir_p!(root)
    File.write!(path, source)

    try do
      Parser.parse_file(path, root)
    after
      File.rm_rf(root)
    end
  end

  defp changes(head, base) do
    head_by_id = Map.new(head, &{item_id(&1), &1})
    base_by_id = Map.new(base, &{item_id(&1), &1})
    head_ids = Map.keys(head_by_id) |> MapSet.new()
    base_ids = Map.keys(base_by_id) |> MapSet.new()
    common = MapSet.intersection(head_ids, base_ids)

    %{
      added: values(MapSet.difference(head_ids, base_ids), head_by_id),
      removed: values(MapSet.difference(base_ids, head_ids), base_by_id),
      modified:
        common
        |> Enum.filter(&(Map.fetch!(head_by_id, &1) != Map.fetch!(base_by_id, &1)))
        |> Enum.sort()
        |> Enum.map(
          &%{id: &1, head: Map.fetch!(head_by_id, &1), base: Map.fetch!(base_by_id, &1)}
        ),
      unchanged_ids:
        common
        |> Enum.reject(&(Map.fetch!(head_by_id, &1) != Map.fetch!(base_by_id, &1)))
        |> MapSet.new()
    }
  end

  defp values(ids, items), do: ids |> Enum.sort() |> Enum.map(&Map.fetch!(items, &1))
  defp item_id(item) when is_struct(item), do: Map.get(item, :id)
  defp item_id(item) when is_map(item), do: Map.get(item, :id) || Map.get(item, "id")
  defp field(nil, _key), do: []
  defp field(map, key), do: Map.get(map, key, [])
end
