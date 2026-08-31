defmodule Ancora.Derive do
  @moduledoc """
  Data construction for source-derived call resolution.

  VM introspection is confined to this module. `Ancora.Derive.Resolver`
  receives the resulting maps, sets, and functions and remains pure.
  """

  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership
  alias Ancora.Derive.Resolver
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

  @type subject_set :: %{
          subject_id: String.t(),
          side: side(),
          bindings: MapSet.t(binding()),
          generated: MapSet.t(binding()),
          dep_generated: MapSet.t(binding()),
          unresolved: [Resolver.unresolved()],
          test_files: [Path.t()],
          findings: [Finding.t()]
        }

  @doc """
  Resolves all tagged test files for one diff side and groups them by subject.

  `subject_files` maps subject ids to test paths. Required options are `:side`
  and a resolver `:context`. `:sources` may be a path-to-source map or a
  function of one path; it defaults to `File.read/1`.
  """
  @spec run(%{String.t() => [Path.t()]}, keyword()) ::
          {:ok, %{String.t() => subject_set()}} | {:error, term()}
  def run(subject_files, opts) when is_map(subject_files) and is_list(opts) do
    side = Keyword.fetch!(opts, :side)
    ctx = Keyword.fetch!(opts, :context)
    sources = Keyword.get(opts, :sources, &File.read/1)

    subject_files
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Task.async_stream(
      &resolve_file(&1, side, ctx, sources),
      ordered: false,
      timeout: :infinity,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.reduce_while({:ok, %{}}, &collect_resolution/2)
    |> case do
      {:ok, resolutions} -> {:ok, build_subject_sets(subject_files, side, ctx, resolutions)}
      {:error, _reason} = error -> error
    end
  end

  @doc "Returns the complete derived call set, including generated bindings."
  @spec all_bindings(subject_set()) :: MapSet.t(binding())
  def all_bindings(subject_set) when is_map(subject_set) do
    MapSet.union(
      Map.get(subject_set, :bindings, MapSet.new()),
      Map.get(subject_set, :generated, MapSet.new())
    )
  end

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

  defp resolve_file(path, side, ctx, sources) do
    with {:ok, source} <- read_source(sources, path),
         {:ok, result} <- Resolver.resolve(source, path, Map.put(ctx, :side, side)) do
      {:ok, path, result}
    end
  end

  defp read_source(sources, path) when is_map(sources) do
    case Map.fetch(sources, path) do
      {:ok, source} when is_binary(source) -> {:ok, source}
      {:ok, other} -> {:error, {:invalid_source, path, other}}
      :error -> {:error, {:source_read, path, :enoent}}
    end
  end

  defp read_source(source_reader, path) when is_function(source_reader, 1) do
    case source_reader.(path) do
      source when is_binary(source) -> {:ok, source}
      {:ok, source} when is_binary(source) -> {:ok, source}
      {:error, reason} -> {:error, {:source_read, path, reason}}
      other -> {:error, {:invalid_source, path, other}}
    end
  end

  defp collect_resolution({:ok, {:ok, path, result}}, {:ok, resolutions}) do
    {:cont, {:ok, Map.put(resolutions, path, result)}}
  end

  defp collect_resolution({:ok, {:error, reason}}, _acc), do: {:halt, {:error, reason}}
  defp collect_resolution({:exit, reason}, _acc), do: {:halt, {:error, {:resolver_exit, reason}}}

  defp build_subject_sets(subject_files, side, ctx, resolutions) do
    Map.new(subject_files, fn {subject_id, files} ->
      files = Enum.uniq(files)
      results = Enum.map(files, &Map.fetch!(resolutions, &1))
      calls = Enum.reduce(results, MapSet.new(), &MapSet.union(&2, &1.calls))
      {bindings, generated, dep_generated} = classify_calls(calls, ctx)

      subject_set = %{
        subject_id: subject_id,
        side: side,
        bindings: bindings,
        generated: generated,
        dep_generated: dep_generated,
        unresolved: Enum.flat_map(results, & &1.unresolved),
        findings: results |> Enum.flat_map(& &1.findings) |> Enum.uniq(),
        test_files: files
      }

      {subject_id, subject_set}
    end)
  end

  defp classify_calls(calls, ctx) do
    Enum.reduce(calls, {MapSet.new(), MapSet.new(), MapSet.new()}, fn binding, classification ->
      classify_call(binding, ctx, classification)
    end)
  end

  defp classify_call({module, name, arity} = binding, ctx, {bindings, generated, dep}) do
    case ctx.def_index.(module) do
      {:ok, index} ->
        if DefIndex.defined?(index, module, name, arity) do
          {MapSet.put(bindings, binding), generated, dep}
        else
          classify_generated(binding, index, module, ctx, {bindings, generated, dep})
        end

      :unknown ->
        {bindings, MapSet.put(generated, binding), MapSet.put(dep, binding)}
    end
  end

  defp classify_generated(binding, index, module, ctx, {bindings, generated, dep}) do
    member_injectors =
      index
      |> DefIndex.uses(module)
      |> Enum.filter(&ctx.membership.(&1))

    if member_injectors == [] do
      {bindings, MapSet.put(generated, binding), MapSet.put(dep, binding)}
    else
      Enum.reduce(member_injectors, {bindings, MapSet.put(generated, binding), dep}, fn injector,
                                                                                        acc ->
        classify_companion(module_from_name(injector), ctx, acc)
      end)
    end
  end

  defp classify_companion(injector, ctx, {bindings, generated, dep}) do
    companion = {injector, :__using__, 1}

    case ctx.def_index.(injector) do
      {:ok, index} ->
        if DefIndex.defined?(index, injector, :__using__, 1) do
          {MapSet.put(bindings, companion), generated, dep}
        else
          {bindings, MapSet.put(generated, companion), dep}
        end

      :unknown ->
        {bindings, MapSet.put(generated, companion), dep}
    end
  end

  defp module_from_name(name) when is_binary(name), do: Module.concat(String.split(name, "."))

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
