Code.require_file("../../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.Derive.MembershipTest do
  use ExUnit.Case, async: true

  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.Membership
  alias Ancora.Derive.RunContext
  alias Ancora.ProjectInfo
  alias Ancora.TmpGitRepo

  setup do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    {:ok, root: root}
  end

  @tag spec: "ancora.derive.membership_source_derived"
  test "a deleted module remains a base member only", %{root: root} do
    # Would fail if Membership reused HEAD for both sides or read compiled
    # membership. The only definition of Legacy comes from ChangeSet's real
    # base-blob prefetch through Ancora.Git.read_blob/2.
    TmpGitRepo.write!(root, %{
      "lib/legacy.ex" => "defmodule Legacy do\n  def run, do: :ok\nend\n"
    })

    TmpGitRepo.commit!(root, "initial")
    File.rm!(Path.join(root, "lib/legacy.ex"))

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, change_set} = ChangeSet.compute(ctx)

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["lib"]}
    assert {:ok, membership} = Membership.load(project, change_set)

    assert Membership.member?(membership, :base, Legacy)
    refute Membership.member?(membership, :head, Legacy)
  end

  @tag spec: "ancora.derive.membership_source_derived"
  test "membership is exactly the locator's per-side source set", %{root: root} do
    TmpGitRepo.write!(root, %{
      "lib/existing.ex" => "defmodule Existing do\nend\n"
    })

    TmpGitRepo.commit!(root, "initial")

    TmpGitRepo.write!(root, %{
      "lib/new_module.ex" => "defprotocol NewProtocol do\n  def run(value)\nend\n"
    })

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, change_set} = ChangeSet.compute(ctx)

    project = %ProjectInfo{root: root, app: :sample, lib_paths: ["lib"]}
    assert {:ok, membership} = Membership.load(project, change_set)

    assert Membership.member?(membership, :head, Existing)
    assert Membership.member?(membership, :base, Existing)
    assert Membership.member?(membership, :head, NewProtocol)
    refute Membership.member?(membership, :base, NewProtocol)
  end

  @tag spec: "ancora.derive.project_info_from_root"
  @tag spec: "ancora.derive.membership_source_derived"
  test "trailing slash config keeps a deleted module in base membership", %{root: root} do
    # Would fail if ModuleLocator rejected the deleted source while rebuilding
    # base membership from the change set.
    TmpGitRepo.write!(root, %{
      "mix.exs" => """
      defmodule Sample.MixProject do
        use Mix.Project
        def project, do: [app: :sample]
      end
      """,
      ".spec/config.yml" => "lib_paths:\n  - src/\n",
      "src/legacy.ex" => "defmodule Legacy do\nend\n",
      "src/thing.ex" => "defmodule Thing do\nend\n"
    })

    TmpGitRepo.commit!(root, "initial")
    File.rm!(Path.join(root, "src/legacy.ex"))

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)
    assert {:ok, change_set} = ChangeSet.compute(ctx)
    assert {:ok, project} = ProjectInfo.load(root)
    assert {:ok, membership} = Membership.load(project, change_set)

    assert Membership.modules(membership, :base) == MapSet.new(["Legacy", "Thing"])
    assert Membership.modules(membership, :head) == MapSet.new(["Thing"])
  end
end
