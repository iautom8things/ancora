defmodule Ancora.Derive.PipelineTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership

  @moduletag spec: [
               "ancora.derive.generated_bindings",
               "ancora.derive.resolver_is_pure"
             ]

  test "context-built resolver input flows through the pipeline on a real fixture" do
    fixture = Path.expand("../../fixtures/resolver/real_shapes.exs", __DIR__)
    source = File.read!(fixture)

    membership = %Membership{
      head:
        MapSet.new([
          "MyApp.Accounts",
          "MyApp.Assertions",
          "MyApp.Factory",
          "MyApp.Schema",
          "MyAppWeb.RouteHelpers"
        ]),
      base: MapSet.new()
    }

    {:ok, ctx} = Derive.context({:ok, membership}, :head, %{})

    assert {:ok, %{"ancora.derive" => subject_set}} =
             Derive.run(%{"ancora.derive" => [fixture]},
               side: :head,
               context: ctx,
               sources: %{fixture => source}
             )

    assert MapSet.size(Derive.all_bindings(subject_set)) > 0
    assert subject_set.side == :head
    assert subject_set.test_files == [fixture]
  end

  test "macro_injected_api_drifts_via_companion and dependency-generated calls stay distinct" do
    indexes = %{
      MyApp.User =>
        index!("""
        defmodule MyApp.User do
          use MyApp.Schema
        end
        """),
      MyApp.Schema =>
        index!("""
        defmodule MyApp.Schema do
          defmacro __using__(_options) do
            quote do
              def changeset(value, attrs), do: {value, attrs}
            end
          end
        end
        """),
      MyApp.Repo =>
        index!("""
        defmodule MyApp.Repo do
          use Ecto.Repo
        end
        """)
    }

    membership = %Membership{
      head: MapSet.new(["MyApp.User", "MyApp.Schema", "MyApp.Repo"]),
      base: MapSet.new()
    }

    {:ok, ctx} = Derive.context({:ok, membership}, :head, indexes)
    path = "test/generated_test.exs"

    source = """
    defmodule GeneratedTest do
      use ExUnit.Case

      test "generated APIs" do
        MyApp.User.changeset(%{}, %{})
        MyApp.Repo.insert(%{})
      end
    end
    """

    assert {:ok, %{"app.subject" => set}} =
             Derive.run(%{"app.subject" => [path]},
               side: :head,
               context: ctx,
               sources: %{path => source}
             )

    assert MapSet.member?(set.generated, {MyApp.User, :changeset, 2})
    assert MapSet.member?(set.bindings, {MyApp.Schema, :__using__, 1})
    assert MapSet.member?(set.generated, {MyApp.Repo, :insert, 1})
    refute MapSet.member?(set.dep_generated, {MyApp.User, :changeset, 2})
    assert MapSet.member?(set.dep_generated, {MyApp.Repo, :insert, 1})
  end

  defp index!(source) do
    {:ok, index} = DefIndex.build(source, "fixture.ex")
    index
  end
end
