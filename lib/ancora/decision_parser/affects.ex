defmodule Ancora.DecisionParser.Affects do
  @moduledoc false

  @type diagnostic :: %{
          code: String.t(),
          severity: :error | :warning,
          message: String.t(),
          decision_id: String.t() | nil,
          detail: String.t() | nil
        }

  @doc """
  Runs `affects:` emptiness and resolution against `decision`.

  An id repeated in `retires:` may be absent from the current index.

  Other specled_ex cross-field rules are not ported.
  """
  @spec validate(map(), map() | MapSet.t(String.t())) :: [diagnostic()]
  def validate(decision, %MapSet{} = resolvable_ids) do
    []
    |> maybe_empty(decision)
    |> maybe_unresolved(decision, resolvable_ids)
    |> Enum.reverse()
  end

  def validate(decision, current_index) do
    validate(decision, resolvable_ids(current_index))
  end

  @doc false
  @spec resolvable_ids(map()) :: MapSet.t(String.t())
  def resolvable_ids(current_index) do
    subjects = list_of(current_index, "subjects")

    subject_ids = collect_ids(subjects, ["meta", "id"])
    requirement_ids = collect_child_ids(subjects, "requirements")
    scenario_ids = collect_child_ids(subjects, "scenarios")
    decision_ids = collect_ids(list_of(current_index, "decisions"), ["meta", "id"])

    MapSet.new(subject_ids ++ requirement_ids ++ scenario_ids ++ decision_ids)
  end

  defp maybe_empty(errors, decision) do
    meta = meta(decision)
    affects = list_field(meta, "affects")

    if affects == [] do
      id = decision_id(decision)

      [
        diagnostic(
          "adr/affects_empty",
          :warning,
          id,
          nil,
          "ADR has empty affects:; name the requirement or subject ids this ADR authorizes"
        )
        | errors
      ]
    else
      errors
    end
  end

  defp maybe_unresolved(errors, decision, resolvable_ids) do
    meta = meta(decision)
    affects = list_field(meta, "affects")

    if affects == [] do
      errors
    else
      resolvable =
        MapSet.union(resolvable_ids, MapSet.new(list_field(meta, "retires")))

      case Enum.find(affects, fn id -> not MapSet.member?(resolvable, id) end) do
        nil ->
          errors

        unresolved ->
          id = decision_id(decision)

          [
            diagnostic(
              "adr/affects_unresolved",
              :error,
              id,
              unresolved,
              "`affects:` id #{inspect(unresolved)} does not resolve in current index"
            )
            | errors
          ]
      end
    end
  end

  defp decision_id(decision) do
    case meta(decision) do
      meta when is_map(meta) ->
        case Map.get(meta, "id") do
          id when is_binary(id) -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp meta(%{"meta" => m}) when is_map(m), do: m
  defp meta(_), do: %{}

  defp list_field(meta, field) when is_map(meta) do
    case Map.get(meta, field) do
      nil ->
        []

      list when is_list(list) ->
        Enum.map(list, fn
          element when is_binary(element) -> element
          element -> inspect(element)
        end)

      _ ->
        []
    end
  end

  defp collect_ids(items, path) do
    items
    |> Enum.map(&get_in_nested(&1, path))
    |> Enum.filter(&is_binary/1)
  end

  defp collect_child_ids(subjects, key) do
    Enum.flat_map(subjects, fn subject ->
      subject
      |> list_of(key)
      |> collect_ids(["id"])
    end)
  end

  defp list_of(map, key) do
    case field(map, key) do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  defp get_in_nested(map, keys) when is_map(map) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{} -> {:cont, field(acc, key)}
        _ -> {:halt, nil}
      end
    end)
  end

  defp get_in_nested(_, _), do: nil

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

  defp diagnostic(code, severity, decision_id, detail, message) do
    %{
      code: code,
      severity: severity,
      message: message,
      decision_id: decision_id,
      detail: detail
    }
  end
end
