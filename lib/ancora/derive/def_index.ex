defmodule Ancora.Derive.DefIndex do
  @moduledoc """
  Source-derived function and macro index for project modules.

  Default arguments expand into every callable arity. Public and private
  definitions are kept separately so imports only resolve public API while
  local-call suppression can include both.
  """

  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]
  @public_kinds [:def, :defmacro, :defguard, :defdelegate]

  defstruct public: %{}, private: %{}, uses: %{}

  @type signature :: {atom(), arity()}
  @type module_name :: String.t()
  @type t :: %__MODULE__{
          public: %{optional(module_name()) => MapSet.t(signature())},
          private: %{optional(module_name()) => MapSet.t(signature())},
          uses: %{optional(module_name()) => MapSet.t(module_name())}
        }

  @doc "Builds an index from source without evaluating it."
  @spec build(binary() | Macro.t(), Path.t()) :: {:ok, t()} | {:error, term()}
  def build(source, path) when is_binary(source) and is_binary(path) do
    case Code.string_to_quoted(source, file: path, emit_warnings: false) do
      {:ok, ast} -> {:ok, collect(ast, [], %__MODULE__{})}
      {:error, reason} -> {:error, {:unparseable_source, path, reason}}
    end
  end

  def build(ast, path) when is_binary(path) do
    {:ok, collect(ast, [], %__MODULE__{})}
  end

  @doc "True when the module has a public definition at the given name and arity."
  @spec public?(t(), module() | String.t(), atom(), arity()) :: boolean()
  def public?(%__MODULE__{public: public}, module, name, arity) do
    public
    |> Map.get(module_name(module), MapSet.new())
    |> MapSet.member?({name, arity})
  end

  @doc "True when the module has a public or private definition."
  @spec defined?(t(), module() | String.t(), atom(), arity()) :: boolean()
  def defined?(%__MODULE__{} = index, module, name, arity) do
    public?(index, module, name, arity) or
      index.private
      |> Map.get(module_name(module), MapSet.new())
      |> MapSet.member?({name, arity})
  end

  @doc "Returns the literal modules used by `module`."
  @spec uses(t(), module() | String.t()) :: MapSet.t(module_name())
  def uses(%__MODULE__{uses: uses}, module) do
    Map.get(uses, module_name(module), MapSet.new())
  end

  defp collect({kind, _, [name_ast, body]}, parent, index)
       when kind in [:defmodule, :defprotocol] and is_list(body) do
    with {:ok, segments, absolute?} <- literal_segments(name_ast),
         {:ok, nested_body} <- Keyword.fetch(body, :do) do
      module = if absolute?, do: segments, else: parent ++ segments
      collect(nested_body, module, index)
    else
      _ -> index
    end
  end

  defp collect({kind, _, [head | _]} = ast, module, index)
       when kind in @definition_kinds do
    index = add_definition(index, module, kind, head)
    collect_definition_body(ast, module, index)
  end

  defp collect({:use, _, [target | _]}, module, index) do
    case literal_module(target, module) do
      {:ok, used_module} ->
        update_in(index.uses, fn uses ->
          Map.update(uses, Enum.join(module, "."), MapSet.new([used_module]), fn modules ->
            MapSet.put(modules, used_module)
          end)
        end)

      :dynamic ->
        index
    end
  end

  defp collect({:quote, _, _args}, _module, index), do: index

  defp collect(ast, module, index) when is_list(ast) do
    Enum.reduce(ast, index, &collect(&1, module, &2))
  end

  defp collect(ast, module, index) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.reduce(index, &collect(&1, module, &2))
  end

  defp collect(_ast, _module, index), do: index

  defp collect_definition_body({_kind, _, [_head, body]}, module, index) when is_list(body) do
    case Keyword.fetch(body, :do) do
      {:ok, ast} -> collect(ast, module, index)
      :error -> index
    end
  end

  defp collect_definition_body(_ast, _module, index), do: index

  defp add_definition(index, [], _kind, _head), do: index

  defp add_definition(index, module, kind, head) do
    case signature(head) do
      {:ok, name, arities} ->
        field = if kind in @public_kinds, do: :public, else: :private
        module = Enum.join(module, ".")

        Map.update!(index, field, fn definitions ->
          Map.update(definitions, module, MapSet.new(Enum.map(arities, &{name, &1})), fn set ->
            Enum.reduce(arities, set, &MapSet.put(&2, {name, &1}))
          end)
        end)

      :error ->
        index
    end
  end

  defp signature({:when, _, [head | _guards]}), do: signature(head)

  defp signature({name, _, args}) when is_atom(name) and is_list(args) do
    maximum = length(args)
    minimum = maximum - Enum.count(args, &default_argument?/1)
    {:ok, name, minimum..maximum}
  end

  defp signature({name, _, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, name, 0..0}
  end

  defp signature(name) when is_atom(name), do: {:ok, name, 0..0}
  defp signature(_head), do: :error

  defp default_argument?({:\\, _, [_argument, _default]}), do: true
  defp default_argument?(_argument), do: false

  defp literal_module({:__aliases__, _, segments}, current) do
    with {:ok, segments, absolute?} <- literal_segments({:__aliases__, [], segments}) do
      full = if absolute?, do: segments, else: relative_segments(segments, current)
      {:ok, Enum.join(full, ".")}
    else
      _ -> :dynamic
    end
  end

  defp literal_module(module, _current) when is_atom(module) do
    {:ok, module_name(module)}
  end

  defp literal_module(_target, _current), do: :dynamic

  defp relative_segments([{:__MODULE__, _, context} | rest], current)
       when is_atom(context) or is_nil(context),
       do: current ++ rest

  defp relative_segments(segments, _current), do: segments

  defp literal_segments({:__aliases__, _, [:"Elixir" | segments]}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments, true}, else: :dynamic
  end

  defp literal_segments({:__aliases__, _, segments}) do
    valid? =
      Enum.all?(segments, fn
        segment when is_atom(segment) -> true
        {:__MODULE__, _, context} when is_atom(context) or is_nil(context) -> true
        _ -> false
      end)

    if valid?, do: {:ok, segments, false}, else: :dynamic
  end

  defp literal_segments(module) when is_atom(module) do
    module
    |> module_name()
    |> String.split(".")
    |> then(&{:ok, &1, true})
  end

  defp literal_segments(_name), do: :dynamic

  defp module_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")
end
