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

  test "multiple subjects fan in files by path and deduplicate shared work" do
    indexes = %{
      App.Shared => index!("defmodule App.Shared do\n  def run, do: :ok\nend\n"),
      App.Alpha => index!("defmodule App.Alpha do\n  def run, do: :ok\nend\n"),
      App.Beta => index!("defmodule App.Beta do\n  def run, do: :ok\nend\n")
    }

    membership = %Membership{
      head: MapSet.new(["App.Shared", "App.Alpha", "App.Beta"]),
      base: MapSet.new()
    }

    {:ok, ctx} = Derive.context({:ok, membership}, :head, indexes)
    caller = self()

    sources = %{
      "test/shared_test.exs" => call_source(App.Shared),
      "test/alpha_test.exs" => call_source(App.Alpha),
      "test/beta_test.exs" => call_source(App.Beta)
    }

    source_reader = fn path ->
      send(caller, {:source_read, path})
      Map.fetch(sources, path)
    end

    subject_files = %{
      "app.alpha" => ["test/shared_test.exs", "test/alpha_test.exs", "test/alpha_test.exs"],
      "app.beta" => ["test/beta_test.exs", "test/shared_test.exs"]
    }

    assert {:ok, %{"app.alpha" => alpha, "app.beta" => beta}} =
             Derive.run(subject_files, side: :head, context: ctx, sources: source_reader)

    assert alpha.test_files == ["test/shared_test.exs", "test/alpha_test.exs"]
    assert beta.test_files == ["test/beta_test.exs", "test/shared_test.exs"]
    assert alpha.bindings == MapSet.new([{App.Shared, :run, 0}, {App.Alpha, :run, 0}])
    assert beta.bindings == MapSet.new([{App.Beta, :run, 0}, {App.Shared, :run, 0}])

    assert_receive {:source_read, "test/shared_test.exs"}
    assert_receive {:source_read, "test/alpha_test.exs"}
    assert_receive {:source_read, "test/beta_test.exs"}
    refute_receive {:source_read, _path}
  end

  test "resolver errors halt the pipeline" do
    membership = %Membership{head: MapSet.new(), base: MapSet.new()}
    {:ok, ctx} = Derive.context({:ok, membership}, :head, %{})

    assert {:error, {:source_read, "test/missing_test.exs", :enoent}} =
             Derive.run(%{"app.subject" => ["test/missing_test.exs"]},
               side: :head,
               context: ctx,
               sources: %{}
             )
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "a raising resolver returns an error without exiting its caller" do
    ctx = %{
      membership: fn _module -> raise "resolver exploded" end,
      ambient: MapSet.new(),
      external_exports: MapSet.new(),
      def_index: fn _module -> :unknown end,
      findings: [],
      side: :head
    }

    source = "defmodule SampleTest do\n  test \"call\", do: Sample.run()\nend\n"

    assert {:error, {:resolver_exception, "test/sample_test.exs", "resolver exploded"}} =
             Derive.run(%{"app.subject" => ["test/sample_test.exs"]},
               side: :head,
               context: ctx,
               sources: %{"test/sample_test.exs" => source}
             )

    assert Process.alive?(self())
  end

  defp index!(source) do
    {:ok, index} = DefIndex.build(source, "fixture.ex")
    index
  end

  defp call_source(module) do
    """
    defmodule PipelineTest do
      use ExUnit.Case

      test "call" do
        #{inspect(module)}.run()
      end
    end
    """
  end
end
