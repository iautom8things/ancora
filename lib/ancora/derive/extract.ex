defmodule Ancora.Derive.Extract do
  @moduledoc """
  Extracts source-ordered clauses for one module, function, and arity.

  Default arguments expand to every callable arity. Attributes adjacent to a
  definition are not part of the returned clause list.
  """

  @definition_kinds [:def, :defmacro, :defguard, :defdelegate]

  @type binding :: Ancora.Derive.binding()

  @doc "Parses source for later clause extraction."
  @spec parse(binary(), Path.t()) :: {:ok, Macro.t()} | {:error, term()}
  def parse(source, path) when is_binary(source) and is_binary(path) do
    case Code.string_to_quoted(source, file: path, emit_warnings: false) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:unparseable_source, path, reason}}
    end
  end

  @doc "Parses source and extracts every clause for `binding`."
  @spec clauses(binary(), Path.t(), binding()) :: {:ok, [Macro.t()]} | {:error, term()}
  def clauses(source, path, {_module, name, arity} = binding)
      when is_binary(source) and is_binary(path) and is_atom(name) and is_integer(arity) do
    case parse(source, path) do
      {:ok, ast} -> {:ok, clauses(ast, binding)}
      {:error, _reason} = error -> error
    end
  end

  @doc "Extracts clauses for `binding` from an already quoted AST."
  @spec clauses(Macro.t(), binding()) :: [Macro.t()]
  def clauses(ast, {module, name, arity}) when is_atom(name) and is_integer(arity) do
    target = module_name(module)
    collect_modules(ast, [], target, name, arity, [])
  end

  defp collect_modules({kind, _, [name_ast, body]}, parent, target, name, arity, clauses)
       when kind in [:defmodule, :defprotocol] and is_list(body) do
    with {:ok, segments, absolute?} <- literal_segments(name_ast),
         {:ok, module_body} <- Keyword.fetch(body, :do) do
      module = if absolute?, do: segments, else: parent ++ segments

      if Enum.join(module, ".") == target do
        collect_definitions(module_body, name, arity, clauses)
      else
        collect_modules(module_body, module, target, name, arity, clauses)
      end
    else
      _ -> clauses
    end
  end

  defp collect_modules({:quote, _, _arguments}, _parent, _target, _name, _arity, clauses),
    do: clauses

  defp collect_modules(ast, parent, target, name, arity, clauses) when is_list(ast) do
    Enum.reduce(ast, clauses, &collect_modules(&1, parent, target, name, arity, &2))
  end

  defp collect_modules(ast, parent, target, name, arity, clauses) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.reduce(clauses, &collect_modules(&1, parent, target, name, arity, &2))
  end

  defp collect_modules(_ast, _parent, _target, _name, _arity, clauses), do: clauses

  defp collect_definitions({kind, _, [head | _]} = clause, name, arity, clauses)
       when kind in @definition_kinds do
    if matching_arity?(head, name, arity), do: clauses ++ [clause], else: clauses
  end

  defp collect_definitions({kind, _, _arguments}, _name, _arity, clauses)
       when kind in [:defmodule, :defprotocol, :quote],
       do: clauses

  defp collect_definitions(ast, name, arity, clauses) when is_list(ast) do
    Enum.reduce(ast, clauses, &collect_definitions(&1, name, arity, &2))
  end

  defp collect_definitions(ast, name, arity, clauses) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.reduce(clauses, &collect_definitions(&1, name, arity, &2))
  end

  defp collect_definitions(_ast, _name, _arity, clauses), do: clauses

  defp matching_arity?({:when, _, [head | _guards]}, name, arity),
    do: matching_arity?(head, name, arity)

  defp matching_arity?({name, _, arguments}, name, arity) when is_list(arguments) do
    maximum = length(arguments)
    minimum = maximum - Enum.count(arguments, &default_argument?/1)
    arity in minimum..maximum
  end

  defp matching_arity?({name, _, context}, name, 0) when is_atom(context) or is_nil(context),
    do: true

  defp matching_arity?(name, name, 0) when is_atom(name), do: true
  defp matching_arity?(_head, _name, _arity), do: false

  defp default_argument?({:\\, _, [_argument, _default]}), do: true
  defp default_argument?(_argument), do: false

  defp literal_segments({:__aliases__, _, [:"Elixir" | segments]}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments, true}, else: :dynamic
  end

  defp literal_segments({:__aliases__, _, segments}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments, false}, else: :dynamic
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
