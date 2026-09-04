Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.PublicApiTest do
  use Ancora.TestCase

  @tag spec: "ancora.parsing.stable_public_api"
  test "Ancora check/2 and validate/2 are documented working entry points", %{root: root} do
    # Would fail if either committed entry point stopped calling its production pipeline.
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" =>
        "defmodule Sample.MixProject do\n  use Mix.Project\n  def project, do: [app: :sample]\nend\n",
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")
    assert {:ok, %{fail: false}} = Ancora.check(root, base: "HEAD")
    assert {:ok, %{fail: false}} = Ancora.validate(root, [])

    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, function_docs} = Code.fetch_docs(Ancora)
    assert moduledoc =~ "semver-stable"

    for name <- [:check, :validate] do
      assert function_exported?(Ancora, name, 2)

      assert Enum.any?(function_docs, fn
               {{:function, ^name, 2}, _, _, %{"en" => doc}, _} -> doc =~ "semver-stable"
               _ -> false
             end)
    end

    readme = File.read!(Path.expand("../../../README.md", __DIR__))
    assert readme =~ "Ancora's semver-stable public API has four functions"
    assert readme =~ "Ancora.check/2"
    assert readme =~ "Ancora.validate/2"
  end
end
