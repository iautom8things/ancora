defmodule Ancora.Derive.ResolverTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ancora.Derive
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Resolver

  @members [
    Foo.Bar,
    Foo.Bar.Baz,
    Foo.Bar.Qux,
    Foo.Bar.Leaf,
    Foo.Bar.Branch,
    Foo.Baz,
    Foo.Qux,
    MyApp.Accounts,
    MyApp.Assertions,
    MyApp.Factory,
    MyApp.Helpers,
    MyApp.Schema,
    MyAppWeb.RouteHelpers,
    Outer.Sub,
    Required.Module
  ]

  setup_all do
    indexes = %{
      MyApp.Assertions => index!(MyApp.Assertions, "def assert_account(value), do: value"),
      MyApp.Factory => index!(MyApp.Factory, "def insert(name), do: name"),
      MyApp.Helpers =>
        index!(MyApp.Helpers, "def helper(value, option \\\\ :default), do: {value, option}"),
      MyAppWeb.RouteHelpers => index!(MyAppWeb.RouteHelpers, "def route_path(conn), do: conn")
    }

    ctx = %{
      membership: &(&1 in @members),
      ambient: Derive.ambient_exports(),
      external_exports: MapSet.new([{Ecto.Query, :from, 2}]),
      def_index: fn module ->
        case Map.fetch(indexes, module) do
          {:ok, index} -> {:ok, index}
          :error -> :unknown
        end
      end,
      findings: [],
      side: :head
    }

    {:ok, ctx: ctx}
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "qualified member call enters the call set", %{ctx: ctx} do
    result = resolve!("Foo.Bar.run(:ok)", ctx)
    assert result.calls == MapSet.new([{Foo.Bar, :run, 1}])
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "qualified dependency call is dropped", %{ctx: ctx} do
    result = resolve!("String.trim(\" value \")", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "pipe adds its left operand to arity without double counting the rhs", %{ctx: ctx} do
    result = resolve!("value |> Foo.Bar.run(:option)", ctx)
    assert result.calls == MapSet.new([{Foo.Bar, :run, 2}])
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "remote capture resolves at its stated arity", %{ctx: ctx} do
    result = resolve!("&Foo.Bar.run/2", ctx)
    assert result.calls == MapSet.new([{Foo.Bar, :run, 2}])
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "local capture is suppressed by the local definition index", %{ctx: ctx} do
    source = """
    defmodule Sample do
      defp helper(left, right), do: {left, right}
      def captured, do: &helper/2
    end
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.dynamic_calls_unresolved"
  test "apply with literal arguments remains unresolved", %{ctx: ctx} do
    result = resolve!("apply(Foo.Bar, :run, [:ok])\napply({Foo.Bar, :run}, [:ok])", ctx)
    assert Enum.map(result.unresolved, &{&1.kind, &1.arity}) == [{:apply, 3}, {:apply, 2}]
    assert result.calls == MapSet.new()
  end

  @tag spec: "ancora.derive.dynamic_calls_unresolved"
  test "variable module calls are unresolved", %{ctx: ctx} do
    result = resolve!("module.run(:ok)", ctx)
    assert [%{kind: :dynamic_module, name: :run, arity: 1}] = result.unresolved
  end

  @tag spec: "ancora.derive.dynamic_calls_unresolved"
  test "variable remote captures fold into dynamic_module", %{ctx: ctx} do
    result = resolve!("&module.run/2", ctx)
    assert [%{kind: :dynamic_module, name: :run, arity: 2}] = result.unresolved
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "no-parens field access is ignored", %{ctx: ctx} do
    result = resolve!("record.field", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "struct literals do not produce bindings", %{ctx: ctx} do
    result = resolve!("%Foo.Bar{value: :ok}", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "use forms do not produce bindings", %{ctx: ctx} do
    result = resolve!("use Foo.Bar", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "project macro DSL calls bind to the macro module", %{ctx: ctx} do
    result = resolve!("MyApp.Schema.field(:name)", ctx)
    assert result.calls == MapSet.new([{MyApp.Schema, :field, 1}])
  end

  @tag spec: "ancora.derive.dynamic_calls_unresolved"
  test "unquote in call position is unresolved", %{ctx: ctx} do
    result = resolve!("quote do\n  unquote(module).run(:ok)\nend", ctx)
    assert [%{kind: :dynamic_module, name: :run, arity: 1}] = result.unresolved
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "unqualified local helper is suppressed", %{ctx: ctx} do
    source = """
    defmodule Sample do
      def helper(value \\\\ :default), do: value
      def run, do: helper()
    end
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "unqualified member import consults its DefIndex", %{ctx: ctx} do
    result = resolve!("import MyApp.Helpers, only: [helper: 1]\nhelper(:value)", ctx)
    assert result.calls == MapSet.new([{MyApp.Helpers, :helper, 1}])
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "external import export is dropped from precomputed context data", %{ctx: ctx} do
    result = resolve!("import Ecto.Query, only: [from: 2]\nfrom(item, in: items)", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "import except filters an otherwise public member definition", %{ctx: ctx} do
    source = """
    import MyApp.Helpers, except: [helper: 2]
    helper(:value)
    helper(:value, :option)
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new([{MyApp.Helpers, :helper, 1}])
    assert [%{kind: :unqualified, name: :helper, arity: 2}] = result.unresolved
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "ambient ExUnit calls are dropped", %{ctx: ctx} do
    result = resolve!("assert true", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.unqualified_ladder"
  test "unknown unqualified calls retain source location", %{ctx: ctx} do
    result = resolve!("\nunknown_helper(:value)", ctx, "test/sample_test.exs")

    assert [
             %{
               kind: :unqualified,
               name: :unknown_helper,
               arity: 1,
               file: "test/sample_test.exs",
               line: 2
             }
           ] = result.unresolved
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "import inside one test body applies to a later test", %{ctx: ctx} do
    source = """
    defmodule SampleTest do
      use ExUnit.Case

      test "first" do
        import MyApp.Helpers, only: [helper: 1]
      end

      test "later" do
        helper(:value)
      end
    end
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new([{MyApp.Helpers, :helper, 1}])
    assert result.unresolved == []
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "alias forms and nested segments resolve through lexical frames", %{ctx: ctx} do
    source = """
    defmodule Outer do
      alias Foo.Bar
      alias Foo.{Baz, Qux}
      alias Foo.Bar, as: B
      alias __MODULE__.Sub
      require Required.Module, as: R

      Bar.run()
      Baz.run()
      Qux.run()
      B.Leaf.run()
      Sub.run()
      R.run()
    end
    """

    result = resolve!(source, ctx)

    assert result.calls ==
             MapSet.new([
               {Foo.Bar, :run, 0},
               {Foo.Baz, :run, 0},
               {Foo.Qux, :run, 0},
               {Foo.Bar.Leaf, :run, 0},
               {Outer.Sub, :run, 0},
               {Required.Module, :run, 0}
             ])
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "aliases declared in a test do not leak into the following sibling", %{ctx: ctx} do
    source = """
    defmodule SampleTest do
      alias Foo.Bar, as: B

      test "inner" do
        alias Foo.Bar.Baz, as: B
        B.run()
      end

      B.run()
    end
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new([{Foo.Bar, :run, 0}, {Foo.Bar.Baz, :run, 0}])
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "aliases do not leak between case branches", %{ctx: ctx} do
    source = """
    defmodule SampleTest do
      alias Foo.Bar, as: B

      case value do
        :first ->
          alias Foo.Bar.Baz, as: B
          B.run()

        :second ->
          B.run()
      end
    end
    """

    result = resolve!(source, ctx)
    assert result.calls == MapSet.new([{Foo.Bar, :run, 0}, {Foo.Bar.Baz, :run, 0}])
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  property "alias stack resolution survives formatter round trips", %{ctx: ctx} do
    check all(leaf <- member_of(["Leaf", "Branch"]), max_runs: 20) do
      source = """
      defmodule Generated do
        alias Foo.Bar, as: B

        test "generated" do
          alias B.#{leaf}, as: Target
          Target.run()
        end
      end
      """

      formatted = source |> Code.format_string!() |> IO.iodata_to_binary()
      expected = Module.concat([Foo.Bar, leaf])

      assert resolve!(source, ctx).calls == MapSet.new([{expected, :run, 0}])
      assert resolve!(formatted, ctx).calls == MapSet.new([{expected, :run, 0}])
    end
  end

  @tag spec: "ancora.derive.resolver_is_pure"
  test "resolver source contains no I/O or VM introspection" do
    source = File.read!(Path.expand("../../../lib/ancora/derive/resolver.ex", __DIR__))

    for forbidden <- ["File.", "IO.", "Code.ensure_loaded?", ".__info__", "Mix.", "Port."] do
      refute source =~ forbidden
    end
  end

  @tag spec: "ancora.derive.resolver_is_pure"
  test "resolver accepts a context made only from functions, maps, and sets" do
    ctx = %{
      membership: &MapSet.member?(MapSet.new([Foo.Bar]), &1),
      ambient: MapSet.new(),
      external_exports: MapSet.new(),
      def_index: fn _module -> :unknown end,
      findings: [],
      side: :head
    }

    assert resolve!("Foo.Bar.run()", ctx).calls == MapSet.new([{Foo.Bar, :run, 0}])
  end

  @tag spec: "ancora.derive.parse_degrades_to_finding"
  test "unparseable base source returns a finding instead of an error", %{ctx: ctx} do
    ctx = %{ctx | side: :base}

    assert {:ok, result} = Resolver.resolve("defmodule Broken do\n", "lib/broken.ex", ctx)
    assert result.calls == MapSet.new()
    assert result.unresolved == []

    assert [%{code: "derived/unparseable_source", file: "lib/broken.ex", message: message}] =
             result.findings

    assert message =~ "at base"
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "real-shape ConnCase, DataCase, comprehension, DSL, and nested imports resolve", %{
    ctx: ctx
  } do
    source = File.read!(Path.expand("../../fixtures/resolver/real_shapes.exs", __DIR__))
    result = resolve!(source, ctx, "test/fixtures/resolver/real_shapes.exs")

    assert result.calls ==
             MapSet.new([
               {MyApp.Accounts, :list, 1},
               {MyApp.Assertions, :assert_account, 1},
               {MyApp.Factory, :insert, 1},
               {MyApp.Schema, :field, 1},
               {MyAppWeb.RouteHelpers, :route_path, 1}
             ])

    assert Enum.any?(result.unresolved, &match?(%{name: :build_conn, arity: 0}, &1))
  end

  @tag spec: "ancora.derive.formatter_round_trip"
  test "ancora source corpus resolves to the same call sets after formatting", %{ctx: ctx} do
    root = Path.expand("../../..", __DIR__)

    paths =
      ["lib/**/*.ex", "test/**/*.ex", "test/**/*.exs"]
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
      |> Enum.uniq()

    for path <- paths do
      source = File.read!(path)
      formatted = source |> Code.format_string!() |> IO.iodata_to_binary()
      relative = Path.relative_to(path, root)

      assert resolve!(source, ctx, relative).calls == resolve!(formatted, ctx, relative).calls,
             relative
    end
  end

  defp resolve!(source, ctx, path \\ "test/sample_test.exs") do
    assert {:ok, result} = Resolver.resolve(source, path, ctx)
    result
  end

  defp index!(module, body) do
    source = "defmodule #{inspect(module)} do\n  #{body}\nend\n"
    assert {:ok, index} = DefIndex.build(source, "lib/generated.ex")
    index
  end
end
