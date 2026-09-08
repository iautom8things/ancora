Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Ancora.Review.FileDiffTest do
  use Ancora.TestCase

  alias Ancora.Review.FileDiff

  @tag spec: "ancora.review.view_model_builder"
  test "diffs retain paths containing spaces, Unicode, quotes, and control characters", %{
    root: root
  } do
    init_git_repo(root)

    paths = [
      "notes with spaces.md",
      "notes é.md",
      "a\"quote.md",
      "a\\slash.md",
      "a\ttab.md",
      "a\nline.md",
      "a\aalert.md",
      "a\eescape.md"
    ]

    write_files(root, Map.new(paths, &{&1, "old\n"}))
    commit_all(root, "base")
    write_files(root, Map.new(paths, &{&1, "new\n"}))
    write_files(root, %{"new\nnotes.md" => "untracked\n"})
    diffs = FileDiff.for_files(root, "HEAD", paths ++ ["new\nnotes.md"])

    assert Map.keys(diffs) |> Enum.sort() == Enum.sort(paths ++ ["new\nnotes.md"])

    for path <- paths do
      assert {:del, "-old"} in diffs[path]
      assert {:add, "+new"} in diffs[path]
    end

    assert {:add, "+untracked"} in diffs["new\nnotes.md"]
  end

  @tag spec: "ancora.review.view_model_builder"
  test "nested project diffs use project-relative paths", %{root: root} do
    init_git_repo(root)
    write_files(root, %{"apps/sample/lib/sample.ex" => "old\n"})
    commit_all(root, "base")
    write_files(root, %{"apps/sample/lib/sample.ex" => "new\n"})
    project = Path.join(root, "apps/sample")

    assert %{"lib/sample.ex" => lines} = FileDiff.for_files(project, "HEAD", ["lib/sample.ex"])
    assert {:del, "-old"} in lines
    assert {:add, "+new"} in lines
  end

  @tag spec: ["ancora.review.view_model_builder", "ancora.gate.only_git_is_spawned"]
  test "review diffs do not execute configured diff or text conversion commands", %{root: root} do
    init_git_repo(root)
    marker = Path.join(root, "driver-ran")
    driver = Path.join(root, "diff-driver")

    write_files(root, %{
      "lib/sample.ex" => "old\n",
      ".gitattributes" => "*.ex diff=custom\n",
      "diff-driver" => "#!/bin/sh\nprintf invoked > '#{marker}'\nprintf filtered\n"
    })

    File.chmod!(driver, 0o755)
    git!(root, ["config", "diff.custom.command", driver])
    git!(root, ["config", "diff.custom.textconv", driver])
    commit_all(root, "base")
    write_files(root, %{"lib/sample.ex" => "new\n"})

    assert %{"lib/sample.ex" => lines} = FileDiff.for_files(root, "HEAD", ["lib/sample.ex"])
    refute File.exists?(marker)
    assert {:del, "-old"} in lines
    assert {:add, "+new"} in lines
  end
end
