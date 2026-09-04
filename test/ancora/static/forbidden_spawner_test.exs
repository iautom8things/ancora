defmodule Ancora.Static.ForbiddenSpawnerTest do
  use ExUnit.Case, async: true

  @lib Path.expand("../../../lib", __DIR__)

  @tag spec: "ancora.gate.only_git_is_spawned"
  test "no subprocess spawn exists outside Ancora.Git" do
    # Would fail if a module outside lib/ancora/git.ex and lib/ancora/git/
    # called System.cmd, System.shell, Port.open, or :os.cmd, so the gate
    # could run something other than git.
    candidates =
      @lib
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()

    assert candidates != []

    detected = Enum.flat_map(candidates, &file_spawn_calls/1)

    assert Enum.any?(detected, fn {path, _kind, _line} -> git_layer?(path) end),
           "spawn detector did not find the known subprocess call in Ancora.Git"

    offenders = Enum.reject(detected, fn {path, _kind, _line} -> git_layer?(path) end)

    assert offenders == []
  end

  defp git_layer?(path) do
    rel = Path.relative_to(path, @lib)
    rel == "ancora/git.ex" or String.starts_with?(rel, "ancora/git/")
  end

  defp file_spawn_calls(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!()
    |> spawn_calls()
    |> Enum.map(fn {kind, line} -> {path, kind, line} end)
  end

  defp spawn_calls(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, [:System]}, name]}, _, _} = node, acc
        when name in [:cmd, :shell] ->
          {node, [{:system, name, meta[:line]} | acc]}

        {{:., meta, [{:__aliases__, _, [:Port]}, :open]}, _, _} = node, acc ->
          {node, [{:port_open, meta[:line]} | acc]}

        {{:., meta, [:os, :cmd]}, _, _} = node, acc ->
          {node, [{:os_cmd, meta[:line]} | acc]}

        {:&, meta, [{:/, _, [{{:., _, [{:__aliases__, _, [:System]}, name]}, _, _}, _arity]}]} =
            node,
        acc
        when name in [:cmd, :shell] ->
          {node, [{:system_capture, name, meta[:line]} | acc]}

        {:&, meta, [{:/, _, [{{:., _, [{:__aliases__, _, [:Port]}, :open]}, _, _}, _arity]}]} =
            node,
        acc ->
          {node, [{:port_open_capture, meta[:line]} | acc]}

        other, acc ->
          {other, acc}
      end)

    Enum.map(acc, fn
      {kind, line} -> {kind, line}
      {kind, _name, line} -> {kind, line}
    end)
  end
end
