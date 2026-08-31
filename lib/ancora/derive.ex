defmodule Ancora.Derive do
  @moduledoc """
  Data construction for source-derived call resolution.

  VM introspection is confined to this module. `Ancora.Derive.Resolver`
  receives the resulting maps, sets, and functions and remains pure.
  """

  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership
  alias Ancora.Finding

  @ambient_modules [
    Kernel,
    Kernel.SpecialForms,
    ExUnit.Case,
    ExUnit.Assertions,
    ExUnit.Callbacks,
    ExUnit.DocTest
  ]

  @type binding :: {module(), atom(), arity()}
  @type side :: :base | :head
  @type resolver_context :: %{
          membership: (module() -> boolean()),
          ambient: MapSet.t({atom(), arity()}),
          external_exports: MapSet.t(binding()),
          def_index: (module() -> {:ok, DefIndex.t()} | :unknown),
          findings: [Finding.t()],
          side: side()
        }

  @doc "Builds the ambient function and macro table once in the tool VM."
  @spec ambient_exports() :: MapSet.t({atom(), arity()})
  def ambient_exports do
    @ambient_modules
    |> Enum.flat_map(&exports/1)
    |> MapSet.new()
  end

  @doc """
  Builds a pure resolver context from per-side membership and DefIndexes.

  `external_modules:` precomputes exports for non-member imports. When module
  location degraded on a parse error, the context carries a finding and an
  empty membership predicate so the detector run can continue.
  """
  @spec context({:ok, Membership.t()} | {:error, term()}, side(), map() | function(), keyword()) ::
          {:ok, resolver_context()}
  def context(membership_result, side, def_indexes, opts \\ []) when side in [:base, :head] do
    {membership, findings, resolved_side} = membership_data(membership_result, side)

    context = %{
      membership: membership,
      ambient: ambient_exports(),
      external_exports: external_exports(Keyword.get(opts, :external_modules, [])),
      def_index: def_index_lookup(def_indexes),
      findings: findings,
      side: resolved_side
    }

    {:ok, context}
  end

  defp membership_data({:ok, %Membership{} = membership}, side) do
    {fn module -> Membership.member?(membership, side, module) end, [], side}
  end

  defp membership_data({:error, {:unparseable_source, side, path, reason}}, _requested_side) do
    finding = unparseable_finding(side, path, reason)
    {fn _module -> false end, [finding], side}
  end

  defp membership_data({:error, reason}, side) do
    raise ArgumentError, "cannot build resolver context: #{inspect(reason)} for #{side}"
  end

  defp def_index_lookup(lookup) when is_function(lookup, 1), do: lookup

  defp def_index_lookup(indexes) when is_map(indexes) do
    fn module ->
      name = module_name(module)

      case Map.fetch(indexes, module) do
        {:ok, index} -> {:ok, index}
        :error -> Map.get(indexes, name, :unknown) |> normalize_index_result()
      end
    end
  end

  defp normalize_index_result(%DefIndex{} = index), do: {:ok, index}
  defp normalize_index_result({:ok, %DefIndex{}} = result), do: result
  defp normalize_index_result(_missing), do: :unknown

  defp external_exports(modules) do
    modules
    |> Enum.flat_map(fn module ->
      Enum.map(exports(module), fn {name, arity} -> {module, name, arity} end)
    end)
    |> MapSet.new()
  end

  defp exports(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__info__, 1) do
      module.__info__(:functions) ++ module.__info__(:macros)
    else
      []
    end
  end

  defp unparseable_finding(side, path, reason) do
    Finding.new(
      code: "derived/unparseable_source",
      file: path,
      message:
        "cannot parse #{path} at #{side} (#{Exception.format_banner(:error, reason)}); " <>
          "drift comparison skipped"
    )
  end

  defp module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")
end
