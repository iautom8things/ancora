defmodule Ancora.Derive.Resolver do
  @moduledoc """
  Pure, two-pass source resolver for calls in tagged test files.

  Pass A indexes local definitions and module-wide imports. Pass B walks calls
  with lexical alias frames and applies the disposition ladder from the
  `ancora.derive` contract.
  """

  alias Ancora.Derive
  alias Ancora.Derive.DefIndex
  alias Ancora.Finding

  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]
  @ignored_forms [:alias, :import, :require, :use]

  @type unresolved_kind :: :unqualified | :dynamic_module | :apply
  @type unresolved :: %{
          kind: unresolved_kind(),
          name: atom() | nil,
          arity: arity() | nil,
          file: Path.t(),
          line: pos_integer()
        }
  @type result :: %{
          calls: MapSet.t(Derive.binding()),
          unresolved: [unresolved()],
          findings: [Finding.t()]
        }

  @doc "Resolves one source file using data supplied by `Ancora.Derive.context/4`."
  @spec resolve(binary(), Path.t(), map()) :: {:ok, result()}
  def resolve(source, path, ctx) when is_binary(source) and is_binary(path) and is_map(ctx) do
    case Code.string_to_quoted(source, file: path, emit_warnings: false) do
      {:ok, ast} ->
        pass_a = index(ast)

        state = %{
          aliases: [%{}],
          calls: MapSet.new(),
          ctx: ctx,
          file: path,
          imports: pass_a.imports,
          local_defs: pass_a.local_defs,
          module: nil,
          unresolved: []
        }

        state = walk(ast, state)

        {:ok,
         %{
           calls: state.calls,
           unresolved: Enum.reverse(state.unresolved),
           findings: Map.get(ctx, :findings, [])
         }}

      {:error, reason} ->
        side = Map.get(ctx, :side, :head)

        finding =
          Finding.new(
            code: "derived/unparseable_source",
            file: path,
            message:
              "cannot parse #{path} at #{side} (#{Exception.format_banner(:error, reason)}); " <>
                "drift comparison skipped"
          )

        {:ok,
         %{
           calls: MapSet.new(),
           unresolved: [],
           findings: [finding | Map.get(ctx, :findings, [])]
         }}
    end
  end

  defp index(ast) do
    initial = %{aliases: %{}, imports: [], local_defs: MapSet.new(), module: nil}
    {_ast, state} = Macro.traverse(ast, initial, &index_pre/2, &index_post/2)
    %{imports: state.imports, local_defs: state.local_defs}
  end

  defp index_pre({kind, _, [head | _]} = ast, state) when kind in @definition_kinds do
    local_defs =
      case signature(head) do
        {:ok, name, arities} ->
          Enum.reduce(arities, state.local_defs, &MapSet.put(&2, {name, &1}))

        :error ->
          state.local_defs
      end

    {ast, %{state | local_defs: local_defs}}
  end

  defp index_pre({:defmodule, _, [module_ast, _body]} = ast, state) do
    module = resolve_module(module_ast, state.aliases, state.module)
    {ast, %{state | module: result_module(module, state.module)}}
  end

  defp index_pre({kind, _, args} = ast, state) when kind in [:alias, :require] do
    aliases = add_aliases(args, state.aliases, state.module)
    {ast, %{state | aliases: aliases}}
  end

  defp index_pre({:import, _, [target | options]} = ast, state) do
    case resolve_module(target, state.aliases, state.module) do
      {:ok, module} ->
        import = import_entry(module, List.first(options) || [])
        {ast, %{state | imports: state.imports ++ [import]}}

      :dynamic ->
        {ast, state}
    end
  end

  defp index_pre(ast, state), do: {ast, state}
  defp index_post(ast, state), do: {ast, state}

  defp walk({:__block__, _, forms}, state), do: walk_forms(forms, state)
  defp walk({:__aliases__, _, _segments}, state), do: state

  defp walk({:defmodule, _, [module_ast, body]}, state) do
    module = resolve_module(module_ast, state.aliases, state.module)

    scoped_state =
      state
      |> push_alias_frame()
      |> Map.put(:module, result_module(module, state.module))

    scoped = walk(keyword_body(body), scoped_state)

    merge_results(state, scoped)
  end

  defp walk({:->, _, [patterns, body]}, state) do
    state = walk(patterns, state)
    scoped = walk(body, push_alias_frame(state))
    merge_results(state, scoped)
  end

  defp walk({kind, _, [_head, body]}, state) when kind in @definition_kinds do
    scoped = walk(keyword_body(body), push_alias_frame(state))
    merge_results(state, scoped)
  end

  defp walk({kind, _, args}, state) when kind in [:alias, :require] do
    %{
      state
      | aliases:
          replace_alias_frame(
            state.aliases,
            add_aliases(args, visible_aliases(state.aliases), state.module)
          )
    }
  end

  defp walk({:import, _, _args}, state), do: state
  defp walk({:use, _, _args}, state), do: state

  defp walk({:quote, _, args}, state), do: walk_call_arguments(args, state)

  defp walk({:%, _, [_module, map]}, state), do: walk(map, state)

  defp walk({:%{}, _, pairs}, state) do
    Enum.reduce(pairs, state, fn
      {_key, value}, acc -> walk(value, acc)
      value, acc -> walk(value, acc)
    end)
  end

  defp walk({:{}, _, elements}, state), do: walk_terms(elements, state)

  defp walk({:|>, _, [left, right]}, state) do
    state = walk(left, state)
    walk_pipe_right(right, state)
  end

  defp walk(
         {:&, meta, [{:/, _, [{{:., _, [target, name]}, _, []}, arity]}]},
         state
       )
       when is_atom(name) and is_integer(arity) do
    state
    |> dispose_qualified(target, name, arity, line(meta))
  end

  defp walk({:&, meta, [{:/, _, [{name, _, context}, arity]}]}, state)
       when is_atom(name) and (is_atom(context) or is_nil(context)) and is_integer(arity) do
    dispose_unqualified(state, name, arity, line(meta))
  end

  defp walk({:&, _, [body]}, state), do: walk(body, state)

  defp walk({:apply, meta, args}, state) when is_list(args) and length(args) in [2, 3] do
    state
    |> add_unresolved(:apply, :apply, length(args), line(meta))
    |> walk_terms(args)
  end

  defp walk({{:unquote, meta, _callee_args}, _call_meta, args}, state) when is_list(args) do
    state
    |> add_unresolved(:dynamic_module, nil, length(args), line(meta))
    |> walk_terms(args)
  end

  defp walk({{:., _, [target, name]}, meta, args}, state) when is_atom(name) and is_list(args) do
    state
    |> dispose_dot_call(target, name, args, meta)
    |> walk_terms(args)
  end

  defp walk({kind, _, [_ | _] = args}, state) when kind in @ignored_forms do
    walk_terms(args, state)
  end

  defp walk({name, meta, args}, state) when is_atom(name) and is_list(args) do
    state = dispose_unqualified(state, name, length(args), line(meta))
    walk_call_arguments(args, state)
  end

  defp walk({_name, _meta, context}, state) when is_atom(context) or is_nil(context), do: state

  defp walk(ast, state) when is_list(ast), do: walk_terms(ast, state)

  defp walk(ast, state) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> walk_terms(state)
  end

  defp walk(_literal, state), do: state

  defp walk_forms(forms, state), do: Enum.reduce(forms, state, &walk/2)

  defp walk_terms(state, terms) when is_map(state) and is_list(terms),
    do: walk_terms(terms, state)

  defp walk_terms(terms, state), do: Enum.reduce(terms, state, &walk/2)

  defp walk_call_arguments(args, state) do
    Enum.reduce(args, state, fn
      options, acc when is_list(options) -> walk_keyword_options(options, acc)
      argument, acc -> walk(argument, acc)
    end)
  end

  defp walk_keyword_options(options, state) do
    Enum.reduce(options, state, fn
      {key, body}, acc when key in [:do, :else, :after, :rescue, :catch] ->
        scoped = walk(body, push_alias_frame(acc))
        merge_results(acc, scoped)

      {_key, value}, acc ->
        walk(value, acc)

      value, acc ->
        walk(value, acc)
    end)
  end

  defp walk_pipe_right({{:., _, [target, name]}, meta, args}, state)
       when is_atom(name) and is_list(args) do
    state
    |> dispose_qualified(target, name, length(args) + 1, line(meta))
    |> walk_terms(args)
  end

  defp walk_pipe_right({name, meta, args}, state) when is_atom(name) and is_list(args) do
    state
    |> dispose_unqualified(name, length(args) + 1, line(meta))
    |> walk_terms(args)
  end

  defp walk_pipe_right(other, state), do: walk(other, state)

  defp dispose_dot_call(state, target, name, args, meta) do
    cond do
      alias_ast?(target) ->
        dispose_qualified(state, target, name, length(args), line(meta))

      unquote_ast?(target) ->
        add_unresolved(state, :dynamic_module, name, length(args), line(meta))

      Keyword.get(meta, :no_parens, false) and args == [] ->
        state

      true ->
        add_unresolved(state, :dynamic_module, name, length(args), line(meta))
    end
  end

  defp dispose_qualified(state, target, name, arity, line) do
    case resolve_module(target, state.aliases, state.module) do
      {:ok, module} ->
        if member?(state.ctx, module) do
          %{state | calls: MapSet.put(state.calls, {module, name, arity})}
        else
          state
        end

      :dynamic ->
        add_unresolved(state, :dynamic_module, name, arity, line)
    end
  end

  defp dispose_unqualified(state, name, arity, line) do
    signature = {name, arity}

    cond do
      MapSet.member?(state.local_defs, signature) ->
        state

      true ->
        dispose_imports(state, name, arity, line)
    end
  end

  defp dispose_imports(state, name, arity, line) do
    disposition =
      Enum.reduce_while(state.imports, :unresolved, fn import, _disposition ->
        if import_admits?(import, {name, arity}) do
          module = import.module

          cond do
            member?(state.ctx, module) and public_definition?(state.ctx, module, name, arity) ->
              {:halt, {:call, module}}

            not member?(state.ctx, module) and
                MapSet.member?(
                  Map.get(state.ctx, :external_exports, MapSet.new()),
                  {module, name, arity}
                ) ->
              {:halt, :drop}

            true ->
              {:cont, :unresolved}
          end
        else
          {:cont, :unresolved}
        end
      end)

    case disposition do
      {:call, module} ->
        %{state | calls: MapSet.put(state.calls, {module, name, arity})}

      :drop ->
        state

      :unresolved ->
        if MapSet.member?(Map.fetch!(state.ctx, :ambient), {name, arity}) do
          state
        else
          add_unresolved(state, :unqualified, name, arity, line)
        end
    end
  end

  defp public_definition?(ctx, module, name, arity) do
    case def_index(ctx, module) do
      {:ok, index} -> DefIndex.public?(index, module, name, arity)
      :unknown -> false
    end
  end

  defp add_unresolved(state, kind, name, arity, line) do
    unresolved = %{kind: kind, name: name, arity: arity, file: state.file, line: line}
    %{state | unresolved: [unresolved | state.unresolved]}
  end

  defp import_entry(module, options) do
    %{
      module: module,
      only: option_signatures(Keyword.get(options, :only)),
      except: option_signatures(Keyword.get(options, :except)) || MapSet.new()
    }
  end

  defp option_signatures(nil), do: nil

  defp option_signatures(signatures) when is_list(signatures) do
    signatures
    |> Enum.flat_map(fn
      {name, arity} when is_atom(name) and is_integer(arity) -> [{name, arity}]
      _other -> []
    end)
    |> MapSet.new()
  end

  defp option_signatures(_dynamic), do: MapSet.new()

  defp import_admits?(%{only: only, except: except}, signature) do
    (is_nil(only) or MapSet.member?(only, signature)) and not MapSet.member?(except, signature)
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

  defp add_aliases([target | options], aliases, current_module) do
    options = List.first(options) || []

    case grouped_aliases(target, aliases, current_module) do
      {:ok, modules} ->
        Enum.reduce(modules, aliases, fn module, acc ->
          name = alias_name(module, Keyword.get(options, :as))
          Map.put(acc, name, module)
        end)

      :dynamic ->
        aliases
    end
  end

  defp add_aliases(_args, aliases, _current_module), do: aliases

  defp grouped_aliases({{:., _, [prefix, :{}]}, _, suffixes}, aliases, current_module) do
    with {:ok, prefix_module} <- resolve_module(prefix, aliases, current_module) do
      modules =
        Enum.flat_map(suffixes, fn suffix ->
          case alias_segments(suffix) do
            {:ok, segments} -> [Module.concat([prefix_module | segments])]
            :dynamic -> []
          end
        end)

      {:ok, modules}
    end
  end

  defp grouped_aliases(target, aliases, current_module) do
    case resolve_module(target, aliases, current_module) do
      {:ok, module} -> {:ok, [module]}
      :dynamic -> :dynamic
    end
  end

  defp alias_name(module, nil) do
    module |> Module.split() |> List.last() |> String.to_existing_atom()
  end

  defp alias_name(_module, {:__aliases__, _, [name]}) when is_atom(name), do: name
  defp alias_name(module, _dynamic), do: alias_name(module, nil)

  defp resolve_module({:__aliases__, _, segments}, aliases, current_module) do
    resolve_segments(segments, aliases, current_module)
  end

  defp resolve_module({:__MODULE__, _, context}, _aliases, current_module)
       when (is_atom(context) or is_nil(context)) and not is_nil(current_module) do
    {:ok, current_module}
  end

  defp resolve_module(module, _aliases, _current_module) when is_atom(module), do: {:ok, module}
  defp resolve_module(_target, _aliases, _current_module), do: :dynamic

  defp resolve_segments([{:__MODULE__, _, context} | rest], _aliases, current_module)
       when (is_atom(context) or is_nil(context)) and not is_nil(current_module) do
    {:ok, Module.concat([current_module | rest])}
  end

  defp resolve_segments([:"Elixir" | rest], _aliases, _current_module),
    do: {:ok, Module.concat(rest)}

  defp resolve_segments([first | rest], aliases, _current_module) when is_atom(first) do
    case lookup_alias(aliases, first) do
      {:ok, module} -> {:ok, Module.concat([module | rest])}
      :error -> {:ok, Module.concat([first | rest])}
    end
  end

  defp resolve_segments(_segments, _aliases, _current_module), do: :dynamic

  defp lookup_alias(aliases, name) when is_list(aliases) do
    Enum.find_value(aliases, :error, fn frame ->
      case Map.fetch(frame, name) do
        {:ok, module} -> {:ok, module}
        :error -> false
      end
    end)
  end

  defp lookup_alias(aliases, name) when is_map(aliases), do: Map.fetch(aliases, name)

  defp alias_segments({:__aliases__, _, segments}) do
    if Enum.all?(segments, &is_atom/1), do: {:ok, segments}, else: :dynamic
  end

  defp alias_segments(_target), do: :dynamic

  defp alias_ast?({:__aliases__, _, _segments}), do: true
  defp alias_ast?({:__MODULE__, _, context}) when is_atom(context) or is_nil(context), do: true
  defp alias_ast?(module) when is_atom(module), do: true
  defp alias_ast?(_target), do: false

  defp unquote_ast?({:unquote, _, _args}), do: true
  defp unquote_ast?(_target), do: false

  defp member?(ctx, module), do: Map.fetch!(ctx, :membership).(module)
  defp def_index(ctx, module), do: Map.fetch!(ctx, :def_index).(module)

  defp keyword_body(body) when is_list(body), do: Keyword.get(body, :do)
  defp keyword_body(_body), do: nil

  defp push_alias_frame(state), do: %{state | aliases: [%{} | state.aliases]}

  defp replace_alias_frame([_current | outer], new_current), do: [new_current | outer]

  defp visible_aliases(frames) do
    frames
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp merge_results(original, scoped) do
    %{original | calls: scoped.calls, unresolved: scoped.unresolved}
  end

  defp result_module({:ok, module}, _fallback), do: module
  defp result_module(:dynamic, fallback), do: fallback

  defp line(meta), do: Keyword.get(meta, :line, 1)
end
