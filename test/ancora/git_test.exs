Code.require_file("../support/tmp_git_repo.exs", __DIR__)
Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.GitTest do
  use Ancora.TestCase, async: false

  alias Ancora.Derive.RunContext
  alias Ancora.Git
  alias Ancora.TmpGitRepo

  setup do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    {:ok, root: root}
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "run returns data when git is absent from PATH", %{root: root} do
    original_path = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", original_path) end)
    System.put_env("PATH", Path.join(root, "no-executables"))

    assert {:error, :git_executable_not_found} = Git.run(root, ["status"])
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight names the remedy when git is absent from PATH", %{root: root} do
    TmpGitRepo.write!(root, %{
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/.keep" => ""
    })

    TmpGitRepo.commit!(root, "initial")

    original_path = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", original_path) end)
    System.put_env("PATH", Path.join(root, "no-executables"))

    assert {:env, message} = Ancora.Gate.Preflight.run(root, base: "HEAD")
    assert message =~ "git executable not found"
    assert message =~ "PATH"
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "ls_tree_entries lists committed blobs", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "a\n", "README.md" => "hi\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, entries} = Git.ls_tree_entries(root, "HEAD")
    paths = entries |> Enum.map(& &1.path) |> Enum.sort()
    assert paths == ["README.md", "lib/a.ex"]
    assert Enum.all?(entries, &(&1.type == "blob" and byte_size(&1.oid) == 40))
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "read_blob uses the run's batch port", %{root: root} do
    # Would fail if the `%BatchPort{}` clause left the port idle and served
    # bytes via `git show` on ctx.root. `git -C` of a directory inside the
    # tmp repo still finds the parent `.git`; the decoy is a sibling under
    # tmp, so show cannot walk into a repo. Git.run(decoy, show) failing
    # pins that; the successful read_blob then cannot have used show.
    TmpGitRepo.write!(root, %{"lib/a.ex" => "defmodule A do\nend\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)

    decoy =
      Path.join(
        Path.dirname(root),
        "ancora-not-a-repo-#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(decoy)
    on_exit(fn -> File.rm_rf(decoy) end)

    refute String.starts_with?(Path.expand(decoy), Path.expand(root) <> "/")

    assert {:error, {:git, ["show", "HEAD:lib/a.ex"], _output, status}} =
             Git.run(decoy, ["show", "HEAD:lib/a.ex"])

    assert status != 0

    isolated = %{ctx | root: decoy}

    assert {:ok, "defmodule A do\nend\n"} = Git.read_blob(isolated, "lib/a.ex")
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "read_blob falls back to git show when the run has no batch port", %{root: root} do
    # Would fail if the show escape hatch were a second function that callers of
    # the batch path could not reach when a git version cannot hold the port.
    TmpGitRepo.write!(root, %{"lib/a.ex" => "show-me\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, ctx} = RunContext.start(root, "HEAD", batch: false)
    on_exit(fn -> RunContext.stop(ctx) end)
    assert ctx.batch_port == nil

    assert {:ok, "show-me\n"} = Git.read_blob(ctx, "lib/a.ex")
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "read_blob keeps successful git show stderr out of blob bytes", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "blob-only\n"})
    TmpGitRepo.commit!(root, "initial")

    alternates = Path.join(root, ".git/objects/info/alternates")
    File.mkdir_p!(Path.dirname(alternates))
    File.write!(alternates, "/definitely/missing/objects\n")

    script = """
    alias Ancora.Derive.RunContext
    alias Ancora.Git
    {:ok, ctx} = RunContext.start(#{inspect(root)}, "HEAD", batch: false)

    try do
      {:ok, payload} = Git.read_blob(ctx, "lib/a.ex")
      IO.binwrite(payload)
    after
      RunContext.stop(ctx)
    end
    """

    result = run_mix_subprocess(["run", "-e", script])
    assert result.status == 0
    assert result.stdout == "blob-only\n"
    assert result.stderr =~ "unable to normalize alternate object path"
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "read_blob accepts a resolved blob oid in the git show fallback", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "show-by-oid\n"})
    TmpGitRepo.commit!(root, "initial")
    oid = TmpGitRepo.git!(root, ["rev-parse", "HEAD:lib/a.ex"])

    assert {:ok, ctx} = RunContext.start(root, "HEAD", batch: false)
    on_exit(fn -> RunContext.stop(ctx) end)

    assert {:ok, "show-by-oid\n"} = Git.read_blob(ctx, String.trim(oid))
  end

  @tag spec: "ancora.derive.memo_is_run_scoped"
  test "memo table is unnamed, public, and gone after stop", %{root: root} do
    TmpGitRepo.write!(root, %{"README.md" => "x\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    assert :ets.info(ctx.memo, :named_table) == false
    assert :ets.info(ctx.memo, :protection) == :public
    assert Port.info(ctx.batch_port.port, :registered_name) == {:registered_name, []}

    :ok = RunContext.memo_put(ctx, :k, :v, :ast)
    assert {:ok, :v, :ast} = RunContext.memo_get(ctx, :k)

    tid = ctx.memo
    port = ctx.batch_port.port
    :ok = RunContext.stop(ctx)

    assert :ets.info(tid) == :undefined
    assert Port.info(port) == nil
  end

  @tag spec: "ancora.derive.memo_is_run_scoped"
  test "memo prefers DefIndex and resolver results over a raw AST", %{root: root} do
    TmpGitRepo.write!(root, %{"README.md" => "x\n"})
    TmpGitRepo.commit!(root, "initial")
    assert {:ok, ctx} = RunContext.start(root, "HEAD")
    on_exit(fn -> RunContext.stop(ctx) end)

    :ok = RunContext.memo_put(ctx, :file, :quoted, :ast)
    :ok = RunContext.memo_put(ctx, :file, :index, :def_index)
    assert {:ok, :index, :def_index} = RunContext.memo_get(ctx, :file)

    :ok = RunContext.memo_put(ctx, :file, :quoted_again, :ast)
    assert {:ok, :index, :def_index} = RunContext.memo_get(ctx, :file)

    :ok = RunContext.memo_put(ctx, :calls, :set, :resolver)
    :ok = RunContext.memo_put(ctx, :calls, :quoted, :ast)
    assert {:ok, :set, :resolver} = RunContext.memo_get(ctx, :calls)
  end

  @tag spec: "ancora.derive.memo_is_run_scoped"
  test "two concurrent runs do not collide", %{root: root} do
    # Would fail if both runs shared one ETS memo: after the barrier, A would
    # observe B's :only_b and B would observe A's :only_a.
    TmpGitRepo.write!(root, %{"README.md" => "a\n"})
    TmpGitRepo.commit!(root, "a")

    root_b = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root_b) end)
    TmpGitRepo.write!(root_b, %{"README.md" => "b\n"})
    TmpGitRepo.commit!(root_b, "b")

    parent = self()

    task_a =
      Task.async(fn ->
        {:ok, ctx} = RunContext.start(root, "HEAD")
        :ok = RunContext.memo_put(ctx, :only_a, :from_a, :blob)
        send(parent, {:ready, :a})

        receive do
          :cross ->
            own = RunContext.memo_get(ctx, :only_a)
            other = RunContext.memo_get(ctx, :only_b)
            named? = :ets.info(ctx.memo, :named_table)
            registered = Port.info(ctx.batch_port.port, :registered_name)
            tid = ctx.memo
            port = ctx.batch_port.port
            :ok = RunContext.stop(ctx)
            {own, other, named?, registered, tid, port}
        end
      end)

    task_b =
      Task.async(fn ->
        {:ok, ctx} = RunContext.start(root_b, "HEAD")
        :ok = RunContext.memo_put(ctx, :only_b, :from_b, :blob)
        send(parent, {:ready, :b})

        receive do
          :cross ->
            own = RunContext.memo_get(ctx, :only_b)
            other = RunContext.memo_get(ctx, :only_a)
            named? = :ets.info(ctx.memo, :named_table)
            registered = Port.info(ctx.batch_port.port, :registered_name)
            tid = ctx.memo
            port = ctx.batch_port.port
            :ok = RunContext.stop(ctx)
            {own, other, named?, registered, tid, port}
        end
      end)

    assert_receive {:ready, :a}, 5_000
    assert_receive {:ready, :b}, 5_000
    send(task_a.pid, :cross)
    send(task_b.pid, :cross)

    assert {{:ok, :from_a, :blob}, :error, false, {:registered_name, []}, tid_a, port_a} =
             Task.await(task_a)

    assert {{:ok, :from_b, :blob}, :error, false, {:registered_name, []}, tid_b, port_b} =
             Task.await(task_b)

    assert :ets.info(tid_a) == :undefined
    assert :ets.info(tid_b) == :undefined
    assert Port.info(port_a) == nil
    assert Port.info(port_b) == nil
  end
end
