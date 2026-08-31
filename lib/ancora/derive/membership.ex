defmodule Ancora.Derive.Membership do
  @moduledoc """
  Source-derived project membership for each side of a diff.

  Membership is exactly the set returned by `Ancora.Derive.ModuleLocator`.
  It never consults `.app`, `_build`, or another compiled artifact.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.ModuleLocator
  alias Ancora.ProjectInfo

  @type side :: ModuleLocator.side()

  defstruct head: MapSet.new(), base: MapSet.new()

  @type t :: %__MODULE__{
          head: MapSet.t(String.t()),
          base: MapSet.t(String.t())
        }

  @doc "Builds membership from project source on HEAD and base."
  @spec load(ProjectInfo.t(), ChangeSet.t()) :: {:ok, t()} | {:error, term()}
  def load(%ProjectInfo{} = project, %ChangeSet{} = change_set) do
    with {:ok, locator} <- ModuleLocator.build(project, change_set) do
      {:ok,
       %__MODULE__{
         head: ModuleLocator.modules(locator, :head),
         base: ModuleLocator.modules(locator, :base)
       }}
    end
  end

  @doc "True when `module` has a literal source definition on `side`."
  @spec member?(t(), side(), module() | String.t()) :: boolean()
  def member?(%__MODULE__{} = membership, side, module) when side in [:head, :base] do
    membership
    |> modules(side)
    |> MapSet.member?(module_name(module))
  end

  @doc "Returns module names in the project on `side`."
  @spec modules(t(), side()) :: MapSet.t(String.t())
  def modules(%__MODULE__{head: head}, :head), do: head
  def modules(%__MODULE__{base: base}, :base), do: base

  defp module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")
end
