defmodule Ancora.SubjectFilesTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.ModuleLocator
  alias Ancora.SubjectFiles

  @moduletag spec: "ancora.derive.subject_footprint"

  test "footprint_union is exactly tagged tests plus defining files" do
    locator = %ModuleLocator{
      head: %{"App.A" => "lib/a.ex", "App.B" => "lib/b.ex", "App.Generated" => "lib/g.ex"},
      base: %{}
    }

    subject_set = %{
      subject_id: "app.subject",
      side: :head,
      test_files: ["test/a_test.exs"],
      bindings: MapSet.new([{App.A, :run, 0}, {App.B, :call, 1}]),
      generated: MapSet.new([{App.Generated, :injected, 0}])
    }

    assert SubjectFiles.footprint(subject_set, locator) ==
             MapSet.new(["test/a_test.exs", "lib/a.ex", "lib/b.ex"])
  end
end
