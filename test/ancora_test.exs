Code.require_file("support/ancora_case.exs", __DIR__)

defmodule AncoraTest do
  use Ancora.TestCase

  @tag spec: "ancora.gate.strict_verdict"
  test "validate reports warning counts and applies strict mode", %{root: root} do
    write_files(root, %{".spec/specs/.keep" => ""})
    write_config(root, "test_tags: []\n")

    assert {:ok, normal} = Ancora.validate(root)
    assert normal.checked == %{subjects: 0, requirements: 0, errors: 0, warnings: 1}
    assert normal.errors == 0
    assert normal.warnings == 1
    assert normal.fail == false
    assert normal.pass == true
    assert Enum.map(normal.findings, & &1.code) == ["config/unknown_key"]

    assert {:ok, strict} = Ancora.validate(root, strict: true)
    assert strict.checked == normal.checked
    assert strict.errors == 0
    assert strict.warnings == 1
    assert strict.fail == true
    assert strict.pass == false
  end
end
