Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Mix.Tasks.Spec.ReviewTest do
  use Ancora.TestCase

  @tag spec: "ancora.review.meta_line_shape"
  @tag spec: "ancora.review.output_flag"
  test "writes the chosen output and prints the two-line golden meta shape", %{root: root} do
    init_git_repo(root)

    write_files(root, %{
      "mix.exs" =>
        "defmodule Fixture.MixProject do\n  use Mix.Project\n  def project, do: [app: :fixture]\nend\n",
      ".spec/specs/.keep" => ""
    })

    commit_all(root, "base")

    output =
      capture_io(fn ->
        Mix.Task.reenable("spec.review")
        Mix.Tasks.Spec.Review.run(["--root", root, "--base", "HEAD", "--output", "tmp/r.html"])
      end)

    assert File.exists?(Path.join(root, "tmp/r.html"))
    assert [first, second] = String.split(output, "\n", trim: true)
    assert first =~ ~r/^spec\.review wrote tmp\/r\.html \(\d+ bytes\)$/
    assert second =~ ~r/^  base=HEAD head=[0-9a-f]+ affected_subjects=0 findings=0$/
  end

  @tag spec: "ancora.review.meta_line_shape"
  test "usage errors raise without printing a verdict line" do
    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Mix.Task.reenable("spec.review")
          Mix.Tasks.Spec.Review.run(["--bogus"])
        end
      end)

    refute output =~ "result="
  end
end
