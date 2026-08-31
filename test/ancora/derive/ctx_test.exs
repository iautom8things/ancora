defmodule Ancora.Derive.CtxTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership

  @tag spec: "ancora.derive.resolver_is_pure"
  test "context precomputes ambient and external exports outside the resolver" do
    membership = %Membership{head: MapSet.new(["MyApp.Helpers"]), base: MapSet.new()}

    assert {:ok, index} =
             DefIndex.build("defmodule MyApp.Helpers do\n  def run, do: :ok\nend\n", "helpers.ex")

    assert {:ok, ctx} =
             Derive.context({:ok, membership}, :head, %{MyApp.Helpers => index},
               external_modules: [String]
             )

    assert ctx.membership.(MyApp.Helpers)
    refute ctx.membership.(String)
    assert MapSet.member?(ctx.ambient, {:assert, 1})
    assert MapSet.member?(ctx.external_exports, {String, :trim, 1})
    assert ctx.def_index.(MyApp.Helpers) == {:ok, index}
    assert ctx.def_index.(Missing) == :unknown
  end

  @tag spec: "ancora.derive.parse_degrades_to_finding"
  test "module locator parse errors become findings carried by a usable context" do
    reason = {[line: 1, column: 4], "syntax error before: ", "end"}

    assert {:ok, ctx} =
             Derive.context(
               {:error, {:unparseable_source, :base, "lib/broken.ex", reason}},
               :head,
               %{}
             )

    refute ctx.membership.(Broken)
    assert ctx.side == :base

    assert [%{code: "derived/unparseable_source", file: "lib/broken.ex", message: message}] =
             ctx.findings

    assert message =~ "at base"
  end
end
