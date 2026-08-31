Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.Decision.NewTest do
  use Ancora.TestCase

  @tag spec: "ancora.scaffold.decision_new"
  test "writes the decision shape and force replaces it", %{root: root} do
    id = "myapp.decision.example"
    path = Path.join([root, ".spec", "decisions", "#{id}.md"])

    stdout =
      capture_io(fn ->
        Mix.Tasks.Spec.Decision.New.run([id, "--root", root, "--title", "Example"])
      end)

    assert stdout == "spec.decision.new wrote #{path}\n"
    content = File.read!(path)
    decision = Ancora.DecisionParser.parse_file(path, root)

    assert decision["meta"] == %{
             "affects" => [],
             "date" => Date.to_iso8601(Date.utc_today()),
             "id" => id,
             "status" => "proposed"
           }

    assert decision["title"] == "Example"
    assert decision["sections"] == ["Context", "Decision", "Consequences"]
    refute content =~ "change_type"

    File.write!(path, "edited\n")

    assert_raise Mix.Error, ~r/Decision already exists/, fn ->
      Mix.Tasks.Spec.Decision.New.run([id, "--root", root])
    end

    capture_io(fn -> Mix.Tasks.Spec.Decision.New.run([id, "--root", root, "--force"]) end)
    refute File.read!(path) == "edited\n"
  end
end
