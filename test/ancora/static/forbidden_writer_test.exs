defmodule Ancora.Static.ForbiddenWriterTest do
  use ExUnit.Case, async: true

  @moduletag spec: "ancora.tasks.single_stdout_writer"

  @lib Path.expand("../../../lib", __DIR__)
  @allowed_prefixes [
    Path.join(@lib, "ancora/output.ex"),
    Path.join(@lib, "ancora/output")
  ]

  # Would fail if a lib/ module other than Output grew an IO.puts/1,
  # Mix.shell(), or other stdout write — the emission path nobody enumerated.
  test "no stdout writer exists outside Ancora.Output" do
    candidates = list_elixir_files(@lib)
    assert candidates != []

    detected = Enum.flat_map(candidates, &file_violations/1)

    assert Enum.any?(detected, fn {path, _kind, _line} -> allowed?(path) end),
           "stdout detector did not find the known writer in Ancora.Output"

    violations =
      detected
      |> Enum.reject(fn {path, _kind, _line} -> allowed?(path) end)
      |> Enum.map(&format_violation/1)

    assert violations == [], """
    stdout writers outside lib/ancora/output.ex and lib/ancora/output/:

    #{Enum.join(violations, "\n")}
    """
  end

  defp list_elixir_files(root) do
    Path.wildcard(Path.join(root, "**/*.{ex,exs}"))
  end

  defp allowed?(path) do
    Enum.any?(@allowed_prefixes, fn prefix ->
      path == prefix or String.starts_with?(path, prefix <> "/")
    end)
  end

  defp file_violations(path) do
    source = File.read!(path)

    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        ast
        |> collect([])
        |> Enum.map(fn {kind, line} -> {path, kind, line} end)

      {:error, {meta, err, token}} ->
        [{path, "parse error: #{err}#{token}", meta[:line]}]
    end
  end

  defp format_violation({path, kind, line}) do
    rel = Path.relative_to(path, Path.expand("../../..", __DIR__))
    "#{rel}:#{line} #{kind}"
  end

  defp collect(ast, acc) do
    {_, acc} =
      Macro.prewalk(ast, acc, fn node, acc ->
        case node do
          {{:., meta, [{:__aliases__, _, [:IO]}, fun]}, _, args}
          when fun in [:puts, :write, :inspect] ->
            if stdout_call?(args) do
              {node, [{"IO.#{fun}/#{length(args)}", meta[:line] || 0} | acc]}
            else
              {node, acc}
            end

          {{:., meta, [{:__aliases__, _, [:Mix]}, :shell]}, _, _args} ->
            {node, [{"Mix.shell/0", meta[:line] || 0} | acc]}

          {{:., meta, [{:__aliases__, _, [:Mix, :Shell, :IO]}, _fun]}, _, _} ->
            {node, [{"Mix.Shell.IO", meta[:line] || 0} | acc]}

          {:&, meta, [{:/, _, [{{:., _, [{:__aliases__, _, [:IO]}, fun]}, _, _}, arity]}]}
          when fun in [:puts, :write, :inspect] and arity in [1, 2] ->
            {node, [{"&IO.#{fun}/#{arity}", meta[:line] || 0} | acc]}

          _other ->
            {node, acc}
        end
      end)

    Enum.reverse(acc)
  end

  # Literal :stderr / :standard_error is a diagnostic, not a stdout write.
  # Config, Severity, and Trailer emit [CONFIG] this way until Mix tasks
  # (L9) call Output.config_diagnostic/1 on those paths too.
  defp stdout_call?([:stderr | _]), do: false
  defp stdout_call?([:standard_error | _]), do: false
  defp stdout_call?(_args), do: true
end
