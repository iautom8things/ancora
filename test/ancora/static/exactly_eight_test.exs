defmodule Ancora.Static.ExactlyEightTest do
  use ExUnit.Case, async: true

  @tag spec: "ancora.tasks.exactly_eight"
  test "the package defines exactly eight spec tasks" do
    Mix.Task.load_all()

    task_names =
      Mix.Task.all_modules()
      |> Enum.map(&Mix.Task.task_name/1)
      |> Enum.filter(&String.starts_with?(&1, "spec."))
      |> Enum.sort()

    assert task_names == [
             "spec.check",
             "spec.decision.new",
             "spec.init",
             "spec.next",
             "spec.prime",
             "spec.review",
             "spec.status",
             "spec.validate"
           ]
  end
end
