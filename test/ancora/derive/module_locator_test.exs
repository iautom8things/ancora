Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Ancora.Derive.ModuleLocatorTest do
  use Ancora.TestCase

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.ModuleLocator
  alias Ancora.ProjectInfo

  @tag spec: "ancora.derive.membership_source_derived"
  test "finds nested modules and protocols under configured lib paths", %{root: root} do
    # Would fail if the production locator flattened nested names, only
    # matched defmodule, or scanned the conventional lib directory alone.
    write_files(root, %{
      "src/shape.ex" => """
      defmodule Outer do
        defmodule Inner do
        end
      end

      defprotocol Shape do
        def area(shape)
      end
      """,
      "lib/ignored.ex" => "defmodule Ignored do\nend\n"
    })

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["src"]}

    assert {:ok, locator} = ModuleLocator.build(project, %ChangeSet{})
    assert ModuleLocator.path_for(locator, :head, Outer) == {:ok, "src/shape.ex"}
    assert ModuleLocator.path_for(locator, :head, Outer.Inner) == {:ok, "src/shape.ex"}
    assert ModuleLocator.path_for(locator, :head, Shape) == {:ok, "src/shape.ex"}
    assert ModuleLocator.path_for(locator, :head, Ignored) == :error
    assert locator.base == locator.head
  end

  @tag spec: "ancora.derive.membership_source_derived"
  test "builds distinct base and HEAD maps from prefetched change blobs", %{root: root} do
    write_files(root, %{
      "lib/renamed.ex" => "defmodule Current do\nend\n"
    })

    change_set = %ChangeSet{
      prefetched: %{
        "lib/renamed.ex" => {:ok, "defmodule Legacy do\nend\n"}
      }
    }

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["lib"]}

    assert {:ok, locator} = ModuleLocator.build(project, change_set)
    assert ModuleLocator.path_for(locator, :head, Current) == {:ok, "lib/renamed.ex"}
    assert ModuleLocator.path_for(locator, :head, Legacy) == :error
    assert ModuleLocator.path_for(locator, :base, Legacy) == {:ok, "lib/renamed.ex"}
    assert ModuleLocator.path_for(locator, :base, Current) == :error
  end

  @tag spec: "ancora.derive.membership_source_derived"
  test "does not guess modules with dynamic names", %{root: root} do
    write_files(root, %{
      "lib/dynamic.ex" => """
      name = Module.concat([Dynamic, Name])

      defmodule name do
      end
      """
    })

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["lib"]}

    assert {:ok, locator} = ModuleLocator.build(project, %ChangeSet{})
    assert ModuleLocator.modules(locator, :head) == MapSet.new()
  end

  @tag spec: "ancora.derive.parse_degrades_to_finding"
  test "reports the path-order-first error when several sources are unparseable", %{root: root} do
    slow_error =
      "defmodule SlowError do\n" <>
        String.duplicate("  value = :padding\n", 20_000) <>
        "  def broken(\nend\n"

    write_files(root, %{
      "lib/a_slow_error.ex" => slow_error,
      "lib/z_fast_error.ex" => "defmodule FastError do\n  def broken(\nend\n"
    })

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["lib"]}

    for _run <- 1..5 do
      assert {:error, {:unparseable_source, :head, "lib/a_slow_error.ex", _reason}} =
               ModuleLocator.build(project, %ChangeSet{}),
             "Would fail if parallel parsing selected an error by task completion order or kept the last path error"
    end
  end
end
