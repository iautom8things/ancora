defmodule Mix.Tasks.Spec.JsonReportTest do
  use ExUnit.Case, async: true

  alias Ancora.Gate

  @tag spec: "ancora.tasks.json_report"
  test "JSON report builder supplies one versioned shape for every tier" do
    # Would fail if a consumer had to branch on absent top-level or section keys.
    reports = [
      Gate.json_report(%{tier: :branch, findings: [%{code: "derived/drift"}]}),
      Gate.json_report(%{tier: :env, fail: true, message: "missing base"}),
      Gate.json_report(%{tier: :usage, fail: true, message: "bad flag"}),
      Gate.json_report(%{tier: :branch, fail: false})
    ]

    assert Enum.all?(reports, &(&1.version == 1))
    assert reports |> Enum.map(&Map.keys/1) |> Enum.uniq() |> length() == 1
    assert reports |> Enum.map(&Map.keys(&1.checked)) |> Enum.uniq() |> length() == 1
    assert reports |> Enum.map(&Map.keys(&1.branch)) |> Enum.uniq() |> length() == 1
    assert reports |> Enum.map(&Map.keys(&1.guidance)) |> Enum.uniq() |> length() == 1
  end
end
