Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Ancora.Derive.TestScopeTest do
  use Ancora.TestCase

  alias Ancora.Derive
  alias Ancora.Derive.{DefIndex, Membership}
  alias Ancora.TagScanner

  @tag spec: "ancora.derive.tagged_test_attribution"
  test "sibling tests and unused helpers do not leak but applicable setup does", %{root: root} do
    source = """
    defmodule ScopedTest do
      setup do
        SharedFixture.prepare()
      end
      @tag spec: "alpha.value"
      test "alpha", do: Alpha.value()
      @tag spec: "beta.value"
      test "beta", do: Beta.value()
      test "untagged", do: Unused.call()
      defp unused, do: Unused.call()
    end
    """

    sets = derive(root, source)

    assert sets["alpha"].bindings ==
             MapSet.new([{Alpha, :value, 0}, {SharedFixture, :prepare, 0}])

    assert sets["beta"].bindings == MapSet.new([{Beta, :value, 0}, {SharedFixture, :prepare, 0}])

    assert Enum.any?(
             sets["alpha"].provenance,
             &(&1.binding == {Alpha, :value, 0} and &1.line == 6)
           )
  end

  @tag spec: "ancora.derive.tagged_test_attribution"
  test "describe callbacks and reachable imported or cyclic local helpers stay scoped", %{
    root: root
  } do
    source = """
    defmodule ScopedTest do
      import TestHelpers, only: [alpha: 0]
      describe "one" do
        setup :prepare
        @tag spec: "alpha.value"
        test "works", do: alpha()
      end
      describe "two" do
        @tag spec: "beta.value"
        test "works", do: Beta.value()
      end
      defp prepare(_), do: loop()
      defp loop do
        SharedFixture.prepare()
        loop()
      end
      defp unused, do: Unused.call()
    end
    """

    support = %{
      "test/support/helpers.ex" =>
        "defmodule TestHelpers do\n def alpha, do: Alpha.value()\n def unused, do: Unused.call()\nend"
    }

    sets = derive(root, source, support)

    assert sets["alpha"].bindings ==
             MapSet.new([{Alpha, :value, 0}, {SharedFixture, :prepare, 0}])

    assert sets["beta"].bindings == MapSet.new([{Beta, :value, 0}])
    refute Enum.any?(sets["beta"].provenance, &(&1.file == "test/support/helpers.ex"))
  end

  @tag spec: "ancora.derive.tagged_test_attribution"
  test "an import inside one test cannot affect a sibling test", %{root: root} do
    source = """
    defmodule ScopedTest do
      @tag spec: "alpha.value"
      test "alpha" do
        import TestHelpers
        alpha()
      end
      @tag spec: "beta.value"
      test "beta", do: alpha()
    end
    """

    support = %{
      "test/support/helpers.ex" => "defmodule TestHelpers do\n def alpha, do: Alpha.value()\nend"
    }

    sets = derive(root, source, support)
    assert sets["alpha"].bindings == MapSet.new([{Alpha, :value, 0}])
    assert sets["beta"].bindings == MapSet.new()
    assert [%{name: :alpha}] = sets["beta"].unresolved
  end

  @tag spec: "ancora.derive.tagged_test_attribution"
  test "dynamic dispatch retains known observations without guessing calls", %{root: root} do
    sets =
      derive(root, """
      defmodule ScopedTest do
        @tag spec: "alpha.value"
        test "alpha" do
          Alpha.value()
          apply(module, :unknown, [])
        end
        @tag spec: "beta.value"
        test "beta", do: Beta.value()
      end
      """)

    assert sets["alpha"].bindings == MapSet.new([{Alpha, :value, 0}])
    assert [%{kind: :apply, carrier: _}] = sets["alpha"].unresolved
    assert sets["beta"].unresolved == []
  end

  defp derive(root, source, support \\ %{}) do
    path = Path.join(root, "test/scoped_test.exs")
    write_files(root, %{"test/scoped_test.exs" => source})
    {:ok, entries} = TagScanner.scan_file(path)
    entries = Enum.map(entries, &%{&1 | file: "test/scoped_test.exs"})

    index = %{
      "subjects" =>
        Enum.map(["alpha", "beta"], &%{"id" => &1, "requirements" => [%{"id" => &1 <> ".value"}]})
    }

    carriers = TagScanner.fold_to_subjects(Enum.group_by(entries, & &1.id), index)
    modules = [Alpha, Beta, SharedFixture, Unused]

    production =
      "defmodule Alpha do def value, do: :ok end\ndefmodule Beta do def value, do: :ok end\ndefmodule SharedFixture do def prepare, do: :ok end\ndefmodule Unused do def call, do: :ok end"

    {:ok, definitions} = DefIndex.build(production, "lib/example.ex")
    membership = %Membership{head: MapSet.new(modules, &inspect(&1))}

    {:ok, context} =
      Derive.context({:ok, membership}, :head, Map.new(modules, &{inspect(&1), definitions}))

    files =
      Map.new(carriers, fn {id, entries} -> {id, Enum.uniq(Enum.map(entries, & &1.file))} end)

    assert {:ok, sets} =
             Derive.run(files,
               side: :head,
               context: context,
               sources: %{"test/scoped_test.exs" => source},
               carriers: carriers,
               support_sources: support
             )

    sets
  end

  @tag spec: "ancora.derive.tagged_test_attribution"
  test "parsed scope follows defaulted helpers and reuses fragment results" do
    source = ~S"""
    defmodule ScopedTest do
      test "works", do: helper()
      defp helper(value \\ Alpha.value()), do: helper(value)
    end
    """

    scope = Ancora.Derive.TestScope.build(%{"test/scoped_test.exs" => source})
    assert map_size(scope.parsed) == 1
    [{{file, carrier}, _fragments}] = Map.to_list(scope.tests)

    ctx = %{
      membership: &(&1 in [Alpha, "Alpha"]),
      def_index: fn _ -> :unknown end,
      ambient: Derive.ambient_exports(),
      external_exports: MapSet.new(),
      findings: [],
      side: :head
    }

    scope = Ancora.Derive.TestScope.for_context(scope, ctx)
    entry = %{file: file, carrier: carrier, test_line: 2}
    first = Ancora.Derive.TestScope.resolve(entry, scope, ctx)
    assert first.calls == MapSet.new([{Alpha, :value, 0}])
    second = Ancora.Derive.TestScope.resolve(entry, scope, ctx, first.cache)
    assert second.calls == first.calls
    assert map_size(second.cache) == map_size(first.cache)
    assert map_size(first.cache) == 2
  end
end
