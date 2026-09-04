defmodule Ancora.Static.ExactlyEightTest do
  use ExUnit.Case, async: true

  @tag spec: "ancora.tasks.exactly_eight"
  test "the package defines exactly eight spec tasks" do
    Mix.Task.load_all()

    task_names =
      :ancora
      |> Application.spec(:modules)
      |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?("Elixir.Mix.Tasks.")))
      |> Enum.map(&Mix.Task.task_name/1)
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
    task_modules =
      :ancora
      |> Application.spec(:modules)
      |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?("Elixir.Mix.Tasks.")))

    assert length(task_modules) == 8

    assert Enum.map(task_modules, &{&1, &1.__info__(:attributes)[:requirements]}) ==
             Enum.map(task_modules, &{&1, ["deps.loadpaths"]})
  end
end
