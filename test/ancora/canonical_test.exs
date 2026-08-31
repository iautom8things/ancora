defmodule Ancora.CanonicalTest do
  use ExUnit.Case, async: true

  alias Ancora.Canonical

  @moduletag spec: "ancora.derive.canonical_is_metadata_strip"

  test "canonical_table keeps only parser and metadata equivalences" do
    equal_pairs = [
      {"def f(x), do: x + 1", "def f(x) do\n  x + 1\nend"},
      {"def f(x), do: g(x)", "def f(x), do: g x"},
      {"def f, do: \"one\\ntwo\\n\"", "def f do\n  \"\"\"\n  one\n  two\n  \"\"\"\nend"},
      {"def f, do: 1_000", "def f, do: 1000"}
    ]

    unequal_pairs = [
      {"def f(x), do: x", "def f(value), do: value"},
      {"def f, do: 'abc'", ~S(def f, do: ~c"abc")},
      {"def f, do: \"abc\"", ~S(def f, do: ~s"abc")},
      {"def f(x), do: x\ndef f(:none), do: nil", "def f(:none), do: nil\ndef f(x), do: x"}
    ]

    Enum.each(equal_pairs, fn {left, right} ->
      assert normalize_source(left) == normalize_source(right)
    end)

    Enum.each(unequal_pairs, fn {left, right} ->
      refute normalize_source(left) == normalize_source(right)
    end)
  end

  @tag spec: "ancora.derive.formatter_round_trip"
  test "own_corpus_round_trip compares each file's complete nonempty AST" do
    files = Path.wildcard("{lib,test}/**/*.{ex,exs}")
    assert files != []

    Enum.each(files, fn path ->
      source = File.read!(path)
      raw = Code.string_to_quoted!(source, file: path, emit_warnings: false)
      formatted = source |> Code.format_string!() |> IO.iodata_to_binary()
      formatted_ast = Code.string_to_quoted!(formatted, file: path, emit_warnings: false)

      assert contains_ast_node?(raw), "expected real AST content in #{path}"
      assert Canonical.normalize(raw) == Canonical.normalize(formatted_ast), path
    end)
  end

  defp normalize_source(source) do
    source |> Code.string_to_quoted!(emit_warnings: false) |> Canonical.normalize()
  end

  defp contains_ast_node?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {_form, metadata, _arguments} = node, _found when is_list(metadata) -> {node, true}
        node, found -> {node, found}
      end)

    found?
  end
end
