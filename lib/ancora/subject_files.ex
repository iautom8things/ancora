defmodule Ancora.SubjectFiles do
  @moduledoc """
  Computes subject file footprints from tagged tests and derived definitions.
  """

  alias Ancora.Derive.ModuleLocator

  @doc "Returns one subject's exact test-file and defining-file union."
  @spec footprint(map(), ModuleLocator.t()) :: MapSet.t(Path.t())
  def footprint(subject_set, %ModuleLocator{} = locator) when is_map(subject_set) do
    side = Map.fetch!(subject_set, :side)
    tests = Map.get(subject_set, :test_files, [])
    bindings = Map.get(subject_set, :bindings, MapSet.new())

    defining_files =
      Enum.flat_map(bindings, fn {module, _name, _arity} ->
        case ModuleLocator.path_for(locator, side, module) do
          {:ok, path} -> [path]
          :error -> []
        end
      end)

    MapSet.new(tests ++ defining_files)
  end

  @doc "Builds `%{subject_id => footprint}` for a map of subject sets."
  @spec build(%{String.t() => map()}, ModuleLocator.t()) ::
          %{String.t() => MapSet.t(Path.t())}
  def build(subject_sets, %ModuleLocator{} = locator) when is_map(subject_sets) do
    Map.new(subject_sets, fn {subject_id, subject_set} ->
      {subject_id, footprint(subject_set, locator)}
    end)
  end
end
