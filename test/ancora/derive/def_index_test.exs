defmodule Ancora.Derive.DefIndexTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.DefIndex

  @tag spec: "ancora.derive.unqualified_ladder"
  test "indexes public and private definitions with every default arity" do
    source = """
    defmodule MyApp.Helpers do
      def public(a, b \\\\ :default), do: {a, b}
      defp private(a \\\\ :default), do: a
      defmacro macro(value), do: value
      defguard is_valid(value) when not is_nil(value)
      defdelegate delegated(value), to: Other
    end

    defmodule MyApp.Other do
      def run, do: :ok
    end
    """

    assert {:ok, index} = DefIndex.build(source, "lib/my_app/helpers.ex")

    assert DefIndex.public?(index, MyApp.Helpers, :public, 1)
    assert DefIndex.public?(index, MyApp.Helpers, :public, 2)
    assert DefIndex.public?(index, MyApp.Helpers, :macro, 1)
    assert DefIndex.public?(index, MyApp.Helpers, :is_valid, 1)
    assert DefIndex.public?(index, MyApp.Helpers, :delegated, 1)
    assert DefIndex.defined?(index, MyApp.Helpers, :private, 0)
    assert DefIndex.defined?(index, MyApp.Helpers, :private, 1)
    refute DefIndex.public?(index, MyApp.Helpers, :private, 1)
    assert DefIndex.public?(index, MyApp.Other, :run, 0)
  end

  @tag spec: "ancora.derive.imports_and_aliases"
  test "indexes nested modules independently" do
    source = """
    defmodule Outer do
      def outer, do: :ok

      defmodule Inner do
        def inner, do: :ok
      end
    end
    """

    assert {:ok, index} = DefIndex.build(source, "lib/outer.ex")
    assert DefIndex.public?(index, Outer, :outer, 0)
    assert DefIndex.public?(index, Outer.Inner, :inner, 0)
    refute DefIndex.public?(index, Outer, :inner, 0)
  end

  @tag spec: "ancora.derive.qualified_call_disposition"
  test "collects literal use targets for generated binding comparison" do
    source = """
    defmodule MyApp.User do
      use MyApp.Schema
      use __MODULE__.Fields
    end
    """

    assert {:ok, index} = DefIndex.build(source, "lib/my_app/user.ex")

    assert DefIndex.uses(index, MyApp.User) ==
             MapSet.new(["MyApp.Schema", "MyApp.User.Fields"])
  end
end
