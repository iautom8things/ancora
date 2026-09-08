defmodule Ancora.Derive.TestScope do
  @moduledoc false

  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Resolver
  alias Ancora.TagScanner
  alias Ancora.Finding

  @definitions [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  def build(sources) do
    Enum.reduce(
      sources,
      %{tests: %{}, helpers: %{}, indexes: %{}, errors: %{}, parsed: %{}},
      fn {file, source}, acc ->
        result = parse(source, file)
        acc = %{acc | parsed: Map.put(acc.parsed, file, result)}

        case result do
          {:ok, ast} ->
            ast = TagScanner.annotate(ast)
            {:ok, index} = DefIndex.build(ast, file)

            acc = %{
              acc
              | indexes:
                  Map.merge(
                    acc.indexes,
                    Map.new(Map.keys(index.public) ++ Map.keys(index.private), &{&1, index})
                  )
            }

            modules(ast, nil, [], file, acc)

          {:error, reason} ->
            %{acc | errors: Map.put(acc.errors, file, reason)}

          {:exception, exception} ->
            %{acc | errors: Map.put(acc.errors, file, Exception.message(exception))}
        end
      end
    )
  end

  defp parse(source, file) do
    Code.string_to_quoted(source, file: file, columns: true, emit_warnings: false)
  rescue
    exception -> {:exception, exception}
  end

  def for_context(index, ctx) do
    %{
      index
      | indexes: Map.reject(index.indexes, fn {module, _} -> ctx.membership.(module) end),
        helpers: Map.reject(index.helpers, fn {{module, _, _}, _} -> ctx.membership.(module) end)
    }
  end

  def resolve(entry, index, ctx, cache \\ %{}) do
    key = {entry.file, entry.carrier}
    ctx = helper_context(ctx, index)

    initial = %{
      calls: MapSet.new(),
      unresolved:
        Enum.map(index.errors, fn {file, _} ->
          %{
            file: file,
            line: 0,
            kind: :unparseable_source,
            carrier: entry.carrier,
            test_file: entry.file,
            test_name: Map.get(entry, :test_name),
            test_line: entry.test_line
          }
        end),
      findings:
        Enum.map(index.errors, fn {file, reason} ->
          Finding.new(
            code: "derived/unparseable_source",
            file: file,
            message:
              "cannot parse #{file}: #{inspect(reason)}; fix the source before comparing observations"
          )
        end),
      provenance: [],
      visited: MapSet.new(),
      cache: cache
    }

    result =
      case Map.fetch(index.tests, key) do
        {:ok, fragments} ->
          Enum.reduce(fragments, initial, &visit(&1, index, ctx, entry, [], &2))

        :error ->
          %{
            initial
            | unresolved: [
                %{
                  file: entry.file,
                  line: entry.test_line,
                  kind: :unqualified,
                  name: nil,
                  arity: nil,
                  carrier: entry.carrier,
                  test_file: entry.file
                }
              ]
          }
      end

    %{
      result
      | unresolved:
          Enum.map(
            result.unresolved,
            &Map.merge(&1, %{
              test_file: entry.file,
              test_name: Map.get(entry, :test_name),
              test_line: entry.test_line
            })
          )
    }
  end

  defp helper_context(ctx, index) do
    member = ctx.membership
    lookup = ctx.def_index

    %{
      ctx
      | membership: fn module ->
          member.(module) or Map.has_key?(index.indexes, module_name(module))
        end,
        def_index: fn module ->
          case Map.fetch(index.indexes, module_name(module)) do
            {:ok, value} -> {:ok, value}
            :error -> lookup.(module)
          end
        end
    }
    |> Map.put(:scoped, true)
  end

  defp visit(fragment, index, ctx, entry, chain, acc) do
    key = {fragment.file, fragment.module, fragment.identity}

    if MapSet.member?(acc.visited, key) do
      acc
    else
      acc = %{acc | visited: MapSet.put(acc.visited, key)}

      {result, cache} =
        case Map.fetch(acc.cache, key) do
          {:ok, result} ->
            {result, acc.cache}

          :error ->
            {:ok, result} = Resolver.resolve_ast(fragment.ast, fragment.file, ctx)
            {result, Map.put(acc.cache, key, result)}
        end

      acc = %{acc | cache: cache}
      chain = chain ++ [%{file: fragment.file, line: fragment.line, kind: fragment.kind}]

      acc = %{
        acc
        | unresolved:
            acc.unresolved ++
              Enum.map(
                result.unresolved,
                &Map.merge(&1, %{
                  carrier: entry.carrier,
                  test_file: entry.file,
                  test_name: Map.get(entry, :test_name),
                  test_line: entry.test_line
                })
              ),
          findings: acc.findings ++ result.findings
      }

      Enum.reduce(result.call_sites, acc, fn site, state ->
        {module, name, arity} = site.binding

        case Map.get(index.helpers, {module_name(module), name, arity}) do
          nil ->
            if Map.has_key?(index.indexes, module_name(module)) do
              %{
                state
                | unresolved: [
                    %{
                      file: site.file,
                      line: site.line,
                      kind: :unqualified,
                      name: name,
                      arity: arity,
                      carrier: entry.carrier,
                      test_file: entry.file
                    }
                    | state.unresolved
                  ]
              }
            else
              provenance =
                Map.merge(site, %{
                  carrier: entry.carrier,
                  test_file: entry.file,
                  test_name: Map.get(entry, :test_name),
                  chain: chain
                })

              %{
                state
                | calls: MapSet.put(state.calls, site.binding),
                  provenance: [provenance | state.provenance]
              }
            end

          helpers ->
            helpers =
              if module_name(module) == fragment.module,
                do: Enum.filter(helpers, &(&1.file == fragment.file)),
                else: helpers

            if helpers |> Enum.map(& &1.file) |> Enum.uniq() |> length() == 1 do
              Enum.reduce(helpers, state, &visit(&1, index, ctx, entry, chain, &2))
            else
              %{
                state
                | unresolved: [
                    %{
                      file: site.file,
                      line: site.line,
                      kind: :unqualified,
                      name: name,
                      arity: arity,
                      carrier: entry.carrier,
                      test_file: entry.file
                    }
                    | state.unresolved
                  ]
              }
            end
        end
      end)
    end
  end

  defp modules({:defmodule, _, [name, [do: body]]}, parent, env, file, acc) do
    case module_name_ast(name, parent) do
      nil -> acc
      module -> scope(body, module, env, [], file, acc)
    end
  end

  defp modules({:__block__, _, forms}, parent, env, file, acc),
    do: Enum.reduce(forms, acc, &modules(&1, parent, env, file, &2))

  defp modules(_, _, _, _, acc), do: acc

  defp scope(body, module, inherited_env, inherited_callbacks, file, acc) do
    forms = forms(body)

    stubs =
      Enum.flat_map(forms, fn
        {kind, meta, [head | _]} when kind in @definitions ->
          [{kind, Keyword.put(meta, :ancora_stub, true), [head, [do: nil]]}]

        _ ->
          []
      end)

    {nodes, _env} =
      Enum.map_reduce(forms, inherited_env, fn
        {kind, _, _} = node, env when kind in [:alias, :import, :require, :use] ->
          {nil, env ++ [freeze_module(node, module)]}

        {:defmodule, meta, [name, _]} = node, env ->
          next_env =
            case module_name_ast(name, module) do
              nil -> env
              nested -> env ++ [{:alias, meta, [Module.concat([nested])]}]
            end

          {{node, env}, next_env}

        node, env ->
          {{node, env}, env}
      end)

    nodes = Enum.reject(nodes, &is_nil/1)

    callbacks =
      inherited_callbacks ++
        Enum.flat_map(nodes, fn
          {{kind, meta, args}, env} when kind in [:setup, :setup_all] ->
            [fragment(callback_body(args, meta), module, env, stubs, file, meta, kind)]

          _ ->
            []
        end)

    Enum.reduce(nodes, acc, fn
      {{kind, meta, args}, env}, state when kind in [:test, :property] ->
        fragment = fragment(body(args), module, env, stubs, file, meta, kind)
        key = {file, Keyword.fetch!(meta, :ancora_carrier)}
        %{state | tests: Map.put(state.tests, key, callbacks ++ [fragment])}

      {{:describe, _, args}, env}, state ->
        scope(body(args), module, env ++ stubs, callbacks, file, state)

      {{:for, _, args}, env}, state ->
        scope(body(args), module, env ++ stubs, callbacks, file, state)

      {{:defmodule, _, _} = node, env}, state ->
        modules(node, module, env, file, state)

      {{kind, meta, [head | _] = args}, env}, state when kind in @definitions ->
        case signature(head) do
          {name, arities} ->
            max_arity = Enum.max(arities)

            Enum.reduce(arities, state, fn arity, s ->
              ast =
                if arity == max_arity do
                  if length(args) == 2, do: {kind, meta, [strip_defaults(head), List.last(args)]}
                else
                  defaults = head_defaults(head) |> Enum.take(-(max_arity - arity))
                  {:__block__, meta, defaults ++ [{name, meta, List.duplicate(nil, max_arity)}]}
                end

              if is_nil(ast) do
                s
              else
                fragment = fragment(ast, module, env, stubs, file, meta, kind)
                fragment = %{fragment | identity: {kind, meta, arity}}

                %{
                  s
                  | helpers:
                      Map.update(
                        s.helpers,
                        {module, name, arity},
                        [fragment],
                        &(&1 ++ [fragment])
                      )
                }
              end
            end)

          nil ->
            state
        end

      _, state ->
        state
    end)
  end

  defp fragment(ast, module, env, stubs, file, meta, kind) do
    module_ast = Module.concat([module])

    %{
      ast: {:defmodule, [], [module_ast, [do: {:__block__, [], env ++ stubs ++ [ast]}]]},
      file: file,
      module: module,
      identity: {kind, meta},
      line: Keyword.get(meta, :line, 0),
      kind: kind
    }
  end

  defp freeze_module(ast, module) do
    Macro.prewalk(ast, fn
      {:__MODULE__, _, _} -> Module.concat([module])
      node -> node
    end)
  end

  defp strip_defaults(head) do
    Macro.prewalk(head, fn
      {:\\, _, [pattern, _default]} -> pattern
      node -> node
    end)
  end

  defp head_defaults({:when, _, [head | _]}), do: head_defaults(head)

  defp head_defaults({_, _, args}) when is_list(args) do
    Enum.flat_map(args, fn
      {:\\, _, [_, default]} -> [default]
      _ -> []
    end)
  end

  defp head_defaults(_), do: []

  defp callback_body(args, meta) do
    case body(args) do
      nil ->
        args
        |> List.flatten()
        |> Enum.map(fn
          name when is_atom(name) -> {name, meta, [nil]}
          other -> {:apply, meta, [other, [nil]]}
        end)
        |> then(&{:__block__, [], &1})

      ast ->
        ast
    end
  end

  defp body(args),
    do:
      Enum.find_value(args, fn value ->
        if is_list(value) and Keyword.keyword?(value), do: Keyword.get(value, :do)
      end)

  defp forms({:__block__, _, forms}), do: forms
  defp forms(nil), do: []
  defp forms(form), do: [form]
  defp signature({:when, _, [head | _]}), do: signature(head)

  defp signature({name, _, args}) when is_atom(name) and is_list(args) do
    max = length(args)
    min = max - Enum.count(args, &match?({:\\, _, _}, &1))
    {name, min..max}
  end

  defp signature({name, _, context}) when is_atom(name) and is_atom(context), do: {name, 0..0}
  defp signature(_), do: nil

  defp module_name_ast({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, parent)
       when is_binary(parent),
       do: join_module([parent | rest])

  defp module_name_ast({:__aliases__, _, [:"Elixir" | rest]}, _parent), do: join_module(rest)
  defp module_name_ast({:__aliases__, _, rest}, nil), do: join_module(rest)
  defp module_name_ast({:__aliases__, _, rest}, parent), do: join_module([parent | rest])
  defp module_name_ast(name, _) when is_atom(name), do: module_name(name)
  defp module_name_ast(_, _), do: nil

  defp join_module(parts) do
    if Enum.all?(parts, &(is_atom(&1) or is_binary(&1))), do: Enum.join(parts, ".")
  end

  defp module_name(module) when is_atom(module),
    do: module |> Atom.to_string() |> String.trim_leading("Elixir.")
end
