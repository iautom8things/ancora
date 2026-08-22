Code.require_file("../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.BaseViewTest do
  use ExUnit.Case, async: true

  alias Ancora.BaseView
  alias Ancora.Derive.RunContext
  alias Ancora.TmpGitRepo

  setup do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    {:ok, root: root}
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "blobs reads the base tree through the run's batch port", %{root: root} do
    TmpGitRepo.write!(root, %{
      "lib/a.ex" => "A\n",
      ".spec/specs/s.spec.md" => "spec\n"
    })

    TmpGitRepo.commit!(root, "initial")

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)

    assert {:ok, files} = BaseView.blobs(ctx)
    assert files["lib/a.ex"] == "A\n"
    assert files[".spec/specs/s.spec.md"] == "spec\n"
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize writes base blobs into an isolated workspace", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "keep\n", "lib/gone.ex" => "bye\n"})
    TmpGitRepo.commit!(root, "initial")
    File.rm!(Path.join(root, "lib/gone.ex"))
    TmpGitRepo.commit!(root, "delete gone")

    assert {:ok, temp} = BaseView.materialize(root, "HEAD~1")
    on_exit(fn -> File.rm_rf(temp) end)

    assert File.read!(Path.join(temp, "lib/a.ex")) == "keep\n"
    assert File.read!(Path.join(temp, "lib/gone.ex")) == "bye\n"
    refute String.starts_with?(temp, root)
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "blobs can be narrowed by pathspecs", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "A\n", "test/a_test.exs" => "T\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, files} = BaseView.blobs(root, "HEAD", pathspecs: ["lib"])
    assert Map.keys(files) == ["lib/a.ex"]
  end
end
