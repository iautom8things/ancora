Code.require_file("json.exs", __DIR__)
Code.require_file("result.exs", __DIR__)

ExUnit.start()

defmodule AncoraReplay.ExitStateTest do
  use ExUnit.Case, async: true

  alias AncoraReplay.Json
  alias AncoraReplay.Result

  test "bar met exits zero" do
    assert Result.exit_code([{:met, "drift found"}, {:met, "control clean"}]) == 0
  end

  test "bar failure exits one" do
    assert Result.exit_code([{:failed, "drift missing"}]) == 1
  end

  test "unparseable JSON exits two" do
    assert {:error, reason} = Json.parse("not json\nspec.check result=pass\n")
    assert reason =~ "no JSON report"
    assert Result.exit_code([{:error, reason}]) == 2
  end
end
