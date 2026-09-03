defmodule Ancora.Derive.ExtractTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.Extract

  @moduletag spec: "ancora.derive.clause_extraction"

  test "collects every supported clause in source order after default expansion" do
    source = """
    defmodule Billing do
      @doc "not part of the definition"
      @spec next(integer()) :: integer()
      def next(value, step \\\\ 1) when value > 0, do: value + step
      @deprecated "kept for callers"
      def next(value, step), do: value - step
      defmacro next(value), do: value
      defguard next(value) when is_integer(value)
      defdelegate next(value), to: Billing.V1

      defmodule Nested do
        def next(value), do: value
      end
    end
    """

    assert {:ok, clauses} = Extract.clauses(source, "lib/billing.ex", {Billing, :next, 1})
    assert Enum.map(clauses, &elem(&1, 0)) == [:def, :defmacro, :defguard, :defdelegate]
    refute inspect(clauses) =~ "not part of the definition"
    refute inspect(clauses) =~ "kept for callers"

    assert {:ok, two_arity} =
             Extract.clauses(source, "lib/billing.ex", {Billing, :next, 2})

    assert Enum.map(two_arity, &elem(&1, 0)) == [:def, :def]
  end

  test "returns a parse error as data" do
    assert {:error, {:unparseable_source, "broken.ex", _reason}} =
             Extract.clauses("defmodule Broken do", "broken.ex", {Broken, :run, 0})
  end
end
