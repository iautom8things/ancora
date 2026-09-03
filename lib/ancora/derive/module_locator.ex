defmodule Ancora.Derive.ModuleLocator do
  @moduledoc """
  Locates literal modules in project source on both sides of a diff.

  The scan recognizes `defmodule` and `defprotocol`, including lexically
  nested modules. Modules built through `Module.create/3` or a non-literal
  module name are invisible by design.
  """

  alias Ancora.Derive.ChangeSet
  alias Ancora.ProjectInfo

  @type side :: :head | :base
  @type module_name :: String.t()

  defstruct head: %{}, base: %{}

  @type t :: %__MODULE__{
          head: %{module_name() => String.t()},
          base: %{module_name() => String.t()}
        }

  @doc "Builds the per-side module-to-source maps for a project and change set."
  @spec build(ProjectInfo.t(), ChangeSet.t()) :: {:ok, t()} | {:error, term()}
  def build(%ProjectInfo{} = project, %ChangeSet{} = change_set) do
    with {:ok, head_sources} <- head_sources(project),
         base_sources <- base_sources(project, change_set, head_sources),
         {:ok, head} <- scan_sources(head_sources, :head),
         {:ok, base} <- scan_sources(base_sources, :base) do
      {:ok, %__MODULE__{head: head, base: base}}
    end
  end

  @doc "Returns the path defining `module` on `side`, or `:error`."
  @spec path_for(t(), side(), module() | String.t()) :: {:ok, String.t()} | :error
  def path_for(%__MODULE__{} = locator, side, module) when side in [:head, :base] do
    locator
    |> side_map(side)
    |> Map.fetch(module_name(module))
  end

  @doc "Returns all literal module names found on `side`."
  @spec modules(t(), side()) :: MapSet.t(String.t())
  def modules(%__MODULE__{} = locator, side) when side in [:head, :base] do
    locator
    |> side_map(side)
    |> Map.keys()
    |> MapSet.new()
  end

  defp head_sources(%ProjectInfo{root: root, lib_paths: lib_paths}) do
    lib_paths
    |> Enum.flat_map(fn lib_path ->
      [root, lib_path, "**", "*.{ex,exs}"]
      |> Path.join()
      |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, sources} ->
      case File.read(path) do
        {:ok, source} ->
          relative = Path.relative_to(path, root)
          {:cont, {:ok, Map.put(sources, relative, source)}}

        {:error, reason} ->
          {:halt, {:error, {:source_read, Path.relative_to(path, root), reason}}}
      end
    end)
  end

  defp base_sources(%ProjectInfo{lib_paths: lib_paths}, change_set, head_sources) do
    from_head =
      Map.new(head_sources, fn {path, head_source} ->
        source =
          case Map.get(change_set.prefetched, path, :unchanged) do
            {:ok, base_source} -> base_source
            :unchanged -> head_source
            :missing -> nil
          end

        {path, source}
      end)

    change_set.prefetched
    |> Enum.reduce(from_head, fn
      {path, {:ok, source}}, sources ->
        if source_path?(path, lib_paths), do: Map.put(sources, path, source), else: sources

      {_path, :missing}, sources ->
        sources
    end)
    |> Enum.reject(fn {_path, source} -> is_nil(source) end)
    |> Map.new()
  end

  defp scan_sources(sources, side) do
    Enum.reduce_while(sources, {:ok, %{}}, fn {path, source}, {:ok, modules} ->
      case Code.string_to_quoted(source, file: path, emit_warnings: false) do
        {:ok, ast} ->
          {:cont, {:ok, collect_modules(ast, [], path, modules)}}

        {:error, reason} ->
          {:halt, {:error, {:unparseable_source, side, path, reason}}}
      end
    end)
  end

  defp collect_modules({kind, _, [name_ast, body]}, parent, path, modules)
       when kind in [:defmodule, :defprotocol] and is_list(body) do
    with {:ok, segments, absolute?} <- literal_segments(name_ast),
         {:ok, nested_body} <- Keyword.fetch(body, :do) do
      full_name = if absolute?, do: segments, else: parent ++ segments
      name = Enum.join(full_name, ".")

      nested_body
      |> collect_modules(full_name, path, Map.put_new(modules, name, path))
    else
      _ -> modules
    end
  end

  defp collect_modules({:quote, _, _args}, _parent, _path, modules), do: modules

  defp collect_modules(ast, parent, path, modules) when is_list(ast) do
    Enum.reduce(ast, modules, &collect_modules(&1, parent, path, &2))
  end

  defp collect_modules(ast, parent, path, modules) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.reduce(modules, &collect_modules(&1, parent, path, &2))
  end

  defp collect_modules(_ast, _parent, _path, modules), do: modules

  defp literal_segments({:__aliases__, _, [:"Elixir" | segments]}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments, true}, else: :dynamic
  end

  defp literal_segments({:__aliases__, _, segments}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments, false}, else: :dynamic
  end

  defp literal_segments(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
    |> String.split(".")
    |> then(&{:ok, &1, true})
  end

  defp literal_segments(_name), do: :dynamic

  defp source_path?(path, lib_paths) do
    Path.extname(path) in [".ex", ".exs"] and
      Enum.any?(lib_paths, fn lib_path ->
        path == lib_path or String.starts_with?(path, lib_path <> "/")
      end)
  end

  defp side_map(%__MODULE__{head: head}, :head), do: head
  defp side_map(%__MODULE__{base: base}, :base), do: base

  defp module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")
end
