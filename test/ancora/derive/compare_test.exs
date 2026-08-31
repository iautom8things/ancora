defmodule Ancora.Derive.CompareTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.Compare
  alias Ancora.Derive.ModuleLocator

  @moduletag spec: [
               "ancora.derive.drift_scope_and_dedupe",
               "ancora.derive.growth_and_shrink",
               "ancora.derive.generated_bindings"
             ]

  test "defdelegate_retarget_fires once" do
    binding = {Billing, :next, 1}
    base = "defmodule Billing do\n  defdelegate next(x), to: Billing.V1\nend\n"
    head = "defmodule Billing do\n  defdelegate next(x), to: Billing.V2\nend\n"

    assert [%{code: "derived/drift", subject: "billing"}] =
             compare([binding], [binding], base, head)
  end

  test "doc_only_edit_is_quiet" do
    binding = {Billing, :next, 1}
    base = "defmodule Billing do\n  @doc \"old\"\n  def next(x), do: x + 1\nend\n"
    head = "defmodule Billing do\n  @doc \"new\"\n  def next(x), do: x + 1\nend\n"
    assert compare([binding], [binding], base, head) == []
  end

  test "clause reorder fires drift" do
    binding = {Billing, :next, 1}
    base = "defmodule Billing do\n  def next(0), do: :zero\n  def next(x), do: x\nend\n"
    head = "defmodule Billing do\n  def next(x), do: x\n  def next(0), do: :zero\nend\n"
    assert [%{code: "derived/drift"}] = compare([binding], [binding], base, head)
  end

  test "default_arity_reports_once" do
    bindings = [{Billing, :foo, 1}, {Billing, :foo, 2}]
    base = "defmodule Billing do\n  def foo(a, b \\\\ 1), do: a + b\nend\n"
    head = "defmodule Billing do\n  def foo(a, b \\\\ 1), do: a * b\nend\n"

    assert [%{code: "derived/drift"}] = compare(bindings, bindings, base, head)
  end

  test "unchanged_file_not_parsed" do
    binding = {Billing, :next, 1}
    locator = locator()

    assert [] =
             Compare.compare("billing", set(:base, [binding]), set(:head, [binding]),
               locator: locator,
               change_set: %ChangeSet{},
               source_reader: fn _side, _path -> raise "unchanged source was parsed" end
             )
  end

  test "defimpl edits stay quiet when the protocol definition is unchanged" do
    binding = {Shape, :area, 1}

    locator = %ModuleLocator{
      base: %{"Shape" => "lib/shape.ex"},
      head: %{"Shape" => "lib/shape.ex"}
    }

    assert [] =
             Compare.compare("shape", set(:base, [binding]), set(:head, [binding]),
               locator: locator,
               change_set: %ChangeSet{entries: [%{path: "lib/circle.ex", status: :modified}]},
               source_reader: fn _side, _path -> raise "protocol source was parsed" end
             )
  end

  test "growth and shrink use set difference and cap rendered bindings" do
    growth = for arity <- 0..11, do: {Billing, :new, arity}
    shrink = [{Legacy, :run, 0}]

    findings =
      Compare.compare("billing", set(:base, shrink), set(:head, growth),
        locator: locator(),
        change_set: %ChangeSet{}
      )

    assert [%{code: "derived/growth", message: growth_message}] =
             Enum.filter(findings, &(&1.code == "derived/growth"))

    assert growth_message =~ "+2 more"

    assert [%{code: "derived/shrink", message: shrink_message}] =
             Enum.filter(findings, &(&1.code == "derived/shrink"))

    assert shrink_message =~ "Legacy.run/0"
  end

  test "new_dir_new_test_is_growth and deleted_module_visible_at_base is shrink" do
    new_binding = {Billing, :void, 2}
    old_binding = {Legacy, :run, 0}

    growth =
      Compare.compare("billing", set(:base, []), set(:head, [new_binding]),
        locator: locator(),
        change_set: %ChangeSet{}
      )

    shrink =
      Compare.compare("legacy", set(:base, [old_binding]), set(:head, []),
        locator: locator(),
        change_set: %ChangeSet{}
      )

    assert [%{code: "derived/growth", message: message}] = growth
    assert message =~ "Billing.void/2"
    assert [%{code: "derived/shrink", message: message}] = shrink
    assert message =~ "Legacy.run/0"
  end

  test "macro_injected_api_drifts_via_companion" do
    companion = {MyApp.Schema, :__using__, 1}
    base = macro_source("def changeset(value, attrs), do: {value, attrs}")
    head = macro_source("def changeset(value, attrs), do: Map.merge(value, attrs)")

    locator = %ModuleLocator{
      base: %{"MyApp.Schema" => "lib/schema.ex"},
      head: %{"MyApp.Schema" => "lib/schema.ex"}
    }

    change_set = %ChangeSet{entries: [%{path: "lib/schema.ex", status: :modified}]}

    assert [%{code: "derived/drift"}] =
             Compare.compare("users", set(:base, [companion]), set(:head, [companion]),
               locator: locator,
               change_set: change_set,
               sources: %{base: %{"lib/schema.ex" => base}, head: %{"lib/schema.ex" => head}}
             )
  end

  test "repo_insert_stays_silent when generated on both sides" do
    binding = {MyApp.Repo, :insert, 1}

    assert [] =
             Compare.compare(
               "repo",
               set(:base, [], [binding]),
               set(:head, [], [binding]),
               locator: locator(),
               change_set: %ChangeSet{entries: [%{path: "lib/billing.ex", status: :modified}]}
             )
  end

  test "def_moved_into_use_is_drift" do
    binding = {Billing, :changeset, 2}

    assert [%{code: "derived/drift", message: message}] =
             Compare.compare(
               "billing",
               set(:base, [binding]),
               set(:head, [], [binding]),
               locator: locator(),
               change_set: %ChangeSet{entries: [%{path: "lib/billing.ex", status: :modified}]}
             )

    assert message =~ "definition moved into or out of macro-generated code"
  end

  defp compare(base_bindings, head_bindings, base_source, head_source) do
    Compare.compare("billing", set(:base, base_bindings), set(:head, head_bindings),
      locator: locator(),
      change_set: %ChangeSet{entries: [%{path: "lib/billing.ex", status: :modified}]},
      sources: %{
        base: %{"lib/billing.ex" => base_source},
        head: %{"lib/billing.ex" => head_source}
      }
    )
  end

  defp set(side, bindings, generated \\ []) do
    %{
      subject_id: "billing",
      side: side,
      bindings: MapSet.new(bindings),
      generated: MapSet.new(generated),
      dep_generated: MapSet.new(),
      unresolved: [],
      findings: [],
      test_files: []
    }
  end

  defp locator do
    %ModuleLocator{
      base: %{"Billing" => "lib/billing.ex", "Legacy" => "lib/legacy.ex"},
      head: %{"Billing" => "lib/billing.ex"}
    }
  end

  defp macro_source(body) do
    """
    defmodule MyApp.Schema do
      defmacro __using__(_options) do
        quote do
          #{body}
        end
      end
    end
    """
  end
end
