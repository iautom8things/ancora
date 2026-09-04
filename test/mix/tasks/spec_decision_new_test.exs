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

    error_output =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/Decision already exists/, fn ->
          Mix.Tasks.Spec.Decision.New.run([id, "--root", root])
        end
      end)

    assert error_output == "Decision already exists: #{path}\n"
    refute error_output =~ "result="
    assert File.read!(path) == "edited\n"

    capture_io(fn ->
      Mix.Tasks.Spec.Decision.New.run([
        id,
        "--root",
        root,
        "--title",
        "Example",
        "--force"
      ])
    end)

    decision = Ancora.DecisionParser.parse_file(path, root)

    assert decision["meta"] == %{
             "affects" => [],
             "date" => Date.to_iso8601(Date.utc_today()),
             "id" => id,
             "status" => "proposed"
           }

    assert decision["title"] == "Example"
  end

  @tag spec: "ancora.tasks.gated_emission_paths"
  test "routes invalid arguments through the gated report path" do
    output =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/requires exactly one DECISION_ID/, fn ->
          Mix.Tasks.Spec.Decision.New.run([])
        end
      end)

    assert output == "spec.decision.new requires exactly one DECISION_ID argument\n"
    refute output =~ "result="
  end
end
