Code.require_file("../../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.Derive.ChangeSetTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.RunContext
  alias Ancora.TmpGitRepo

  setup do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    {:ok, root: root}
  end

  @tag spec: "ancora.derive.change_set_union"
  test "a file inside a new untracked directory is listed individually", %{root: root} do
    # Would fail if ChangeSet used `git status --porcelain` without
    # `--untracked-files=all`: git would report `?? test/billing/` and the
    # new tagged test would be absent from the change set, suppressing growth.
    TmpGitRepo.write!(root, %{"lib/billing.ex" => "defmodule Billing do\nend\n"})
    TmpGitRepo.commit!(root, "initial")

    TmpGitRepo.write!(root, %{
      "test/billing/void_test.exs" => """
      defmodule Billing.VoidTest do
        use ExUnit.Case
        @tag spec: "billing.void"
        test "void", do: Billing.void(1, 2)
      end
      """
    })

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, set} = ChangeSet.compute(ctx)

    paths = ChangeSet.paths(set)
    assert "test/billing/void_test.exs" in paths
    refute "test/billing/" in paths
    assert %{path: "test/billing/void_test.exs", status: :untracked} in set.entries
    assert set.prefetched["test/billing/void_test.exs"] == :missing
  end

  @tag spec: "ancora.derive.change_set_union"
  test "git mv plus edit is a delete plus an add with both paths prefetched", %{root: root} do
    # Would fail if ChangeSet omitted `--no-renames`: git would emit an R-row,
    # the old path would drop out of prefetch, and the locator could not see
    # the moved module at base.
    original = "defmodule A do\n  def x, do: 1\nend\n"
    TmpGitRepo.write!(root, %{"lib/a.ex" => original})
    TmpGitRepo.commit!(root, "initial")

    TmpGitRepo.git!(root, ["mv", "lib/a.ex", "lib/b.ex"])
    File.write!(Path.join(root, "lib/b.ex"), "defmodule B do\n  def x, do: 2\nend\n")

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, set} = ChangeSet.compute(ctx)

    by_path = Map.new(set.entries, &{&1.path, &1.status})
    assert by_path["lib/a.ex"] == :deleted
    assert by_path["lib/b.ex"] == :added
    assert set.prefetched["lib/a.ex"] == {:ok, original}
    assert set.prefetched["lib/b.ex"] == :missing
  end

  @tag spec: "ancora.derive.change_set_union"
  test "union includes a dirty tracked file and an untracked file", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "old\n"})
    TmpGitRepo.commit!(root, "initial")
    File.write!(Path.join(root, "lib/a.ex"), "new\n")
    TmpGitRepo.write!(root, %{"notes.txt" => "scratch\n"})

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, set} = ChangeSet.compute(ctx)

    by_path = Map.new(set.entries, &{&1.path, &1.status})
    assert by_path["lib/a.ex"] == :modified
    assert by_path["notes.txt"] == :untracked
    assert set.prefetched["lib/a.ex"] == {:ok, "old\n"}
    assert set.prefetched["notes.txt"] == :missing
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "prefetch goes through git show when the run has no batch port", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "old\n"})
    TmpGitRepo.commit!(root, "initial")
    File.write!(Path.join(root, "lib/a.ex"), "new\n")

    assert {:ok, ctx} = RunContext.start(root, "HEAD", batch: false)
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, set} = ChangeSet.compute(ctx)
    assert set.prefetched["lib/a.ex"] == {:ok, "old\n"}
  end
end
