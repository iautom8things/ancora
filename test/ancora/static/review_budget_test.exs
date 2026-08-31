defmodule Ancora.Static.ReviewBudgetTest do
  use ExUnit.Case, async: true

  @tag spec: "ancora.review.size_budget"
  test "review rendering stays inside its line budget" do
    root = Path.expand("../../..", __DIR__)

    files =
      Path.wildcard(Path.join(root, "lib/ancora/review/*.ex")) ++
        [Path.join(root, "lib/ancora/markdown.ex")]

    counts = Map.new(files, &{&1, &1 |> File.stream!() |> Enum.count()})

    assert Enum.sum(Map.values(counts)) <= 5_000
    assert Enum.all?(counts, fn {_file, count} -> count <= 2_500 end)
  end
end
