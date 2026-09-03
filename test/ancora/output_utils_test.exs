defmodule Ancora.Output.UtilsTest do
  use ExUnit.Case, async: true

  alias Ancora.TaskArgs
  alias Ancora.TempName

  describe "TaskArgs" do
    test "validate returns one error message without raising" do
      assert {:error, "Invalid arguments for spec.check: --unknown, \"extra\""} =
               TaskArgs.validate("spec.check", ["extra"], [{"--unknown", nil}])
    end

    test "validate accepts empty leftovers" do
      assert :ok = TaskArgs.validate("spec.check", [], [])
    end

    test "validate! keeps the raising API" do
      assert_raise Mix.Error, "Invalid arguments for spec.sync: --unknown", fn ->
        TaskArgs.validate!("spec.sync", [], [{"--unknown", nil}])
      end
    end
  end

  describe "TempName" do
    test "cross_vm_suffix is pid plus 12 lowercase hex chars" do
      suffix = TempName.cross_vm_suffix()
      assert suffix =~ ~r/^\d+_[0-9a-f]{12}$/
      assert String.starts_with?(suffix, "#{System.pid()}_")
    end

    test "successive suffixes differ" do
      refute TempName.cross_vm_suffix() == TempName.cross_vm_suffix()
    end
  end
end
