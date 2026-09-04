Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.PrimeTest do
  use Ancora.TestCase

  alias Ancora.Output
  alias Ancora.Prime

  @tag spec: "ancora.tasks.prime_loop"
  test "composes status and next with the check and read-protocol footer", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")

    assert {:ok, report} = Prime.build(root, base: "HEAD")
    assert "Spec Led Prime" == hd(report.lines)
    assert "Status" in report.lines
    assert "Next" in report.lines
    assert Enum.at(report.lines, -2) == "* When ready, run mix spec.check --base HEAD."
    assert List.last(report.lines) == Output.read_protocol()
  end
end
