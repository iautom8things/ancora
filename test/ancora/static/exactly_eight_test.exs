defmodule Ancora.Static.ExactlyEightTest do
  use ExUnit.Case, async: true

  @tag spec: "ancora.tasks.exactly_eight"
  test "the package defines exactly eight spec tasks" do
    Mix.Task.load_all()

    task_names =
      :ancora
      |> Application.spec(:modules)
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

  @tag spec: "ancora.gate.only_git_is_spawned"
  test "every package spec task loads dependencies without compiling the target" do
    spec_tasks =
      :ancora
      |> Application.spec(:modules)
      |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?("Elixir.Mix.Tasks.Spec.")))

    assert length(spec_tasks) == 8

    assert Enum.map(spec_tasks, &{&1, &1.__info__(:attributes)[:requirements]}) ==
             Enum.map(spec_tasks, &{&1, ["deps.loadpaths"]})
  end
end
