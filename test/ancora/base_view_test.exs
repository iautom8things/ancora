Code.require_file("../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.BaseViewTest do
  use ExUnit.Case, async: false

  alias Ancora.BaseView
  alias Ancora.Derive.RunContext
  alias Ancora.TmpGitRepo

  setup do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    {:ok, root: root}
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "blobs reads the base tree through Git.read_blob/2", %{root: root} do
    # Would fail if BaseView called BatchPort.fetch or opened an ephemeral
    # port instead of Git.read_blob/2.
    source = File.read!(Path.expand("lib/ancora/base_view.ex"))
    {:ok, ast} = Code.string_to_quoted(source)
    {_, calls} = blob_read_calls(ast)
    assert {:read_blob, "entry.oid"} in calls
    assert :batch_false in calls
    refute Enum.any?(calls, &match?({:batch_port, _}, &1))

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
  test "blobs falls back to git show when the run has no batch port", %{root: root} do
    # Would fail if BaseView opened an ephemeral BatchPort when the ctx has
    # no port, instead of Git.read_blob/2's git-show clause.
    TmpGitRepo.write!(root, %{"lib/a.ex" => "show-me\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, ctx} = RunContext.start(root, "HEAD", batch: false)
    on_exit(fn -> RunContext.stop(ctx) end)
    assert ctx.batch_port == nil

    assert {:ok, files} = BaseView.blobs(ctx)
    assert files["lib/a.ex"] == "show-me\n"
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
  test "materialize uses a cross-VM name and a non-recursive root mkdir" do
    # Would fail if BaseView restored its VM-local suffix or recursive root creation.
    source = File.read!(Path.expand("lib/ancora/base_view.ex"))
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:TempName]}, :cross_vm_suffix]}, _, []} = node, acc ->
          {node, [:cross_vm_suffix | acc]}

        {{:., _, [{:__aliases__, _, [:File]}, :mkdir]}, _, [_path]} = node, acc ->
          {node, [:mkdir | acc]}

        other, acc ->
          {other, acc}
      end)

    assert :cross_vm_suffix in calls
    assert Enum.count(calls, &(&1 == :mkdir)) == 1
  end

  for depth <- [2, 5], batch <- [false, true] do
    @tag spec: "ancora.derive.base_reads_batched"
    test "materialize rejects traversal depth #{depth} with batch=#{batch} without writing", %{
      root: root
    } do
      depth = unquote(depth)
      components = ["a"] ++ List.duplicate("..", depth) ++ ["evil.txt"]
      base = TmpGitRepo.commit_tree_path!(root, components)
      parent = Path.join(root, "materialization")
      temp = Path.join([parent] ++ List.duplicate("level", depth - 2) ++ ["base"])
      target = Path.expand(Path.join(temp, Enum.join(components, "/")))
      File.mkdir_p!(Path.dirname(temp))

      on_exit(fn ->
        File.rm(target)
        File.rm_rf(parent)
      end)

      assert target == Path.join(parent, "evil.txt")
      assert {:ok, entries} = Ancora.Git.ls_tree_entries(root, base)
      assert Enum.map(entries, & &1.path) == [Enum.join(components, "/")]
      assert {:ok, ctx} = RunContext.start(root, base, batch: unquote(batch))
      on_exit(fn -> RunContext.stop(ctx) end)

      result = BaseView.materialize(ctx, nil, temp_root: temp)

      # Would fail if a hostile path reached the write loop, even if it later returned an error.
      refute File.exists?(target)
      refute File.exists?(temp)

      assert Path.wildcard(Path.join(parent, "**/*"), match_dot: true)
             |> Enum.filter(&File.regular?/1) == []

      assert {:env, message} = result
      assert message =~ "unsafe base tree path"
      assert message =~ Enum.join(components, "/")
    end
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize rejects a dot component", %{root: root} do
    base = TmpGitRepo.commit_tree_path!(root, ["a", ".", "evil.txt"])
    temp = Path.join(root, "base")

    result = BaseView.materialize(root, base, temp_root: temp)

    refute File.exists?(temp)
    assert {:env, message} = result
    assert message =~ "a/./evil.txt"
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize rejects an empty component emitted by a literal tree", %{root: root} do
    input = Path.join(root, ".git/literal-tree")
    File.write!(input, "payload\n")
    blob = root |> TmpGitRepo.git!(["hash-object", "-w", input]) |> String.trim()
    File.write!(input, "100644 a//evil.txt\0" <> Base.decode16!(blob, case: :lower))

    tree =
      root
      |> TmpGitRepo.git!(["hash-object", "-w", "--literally", "-t", "tree", input])
      |> String.trim()

    base = root |> TmpGitRepo.git!(["commit-tree", tree, "-m", "literal tree"]) |> String.trim()
    temp = Path.join(root, "base")

    assert {:ok, [%{path: "a//evil.txt"}]} = Ancora.Git.ls_tree_entries(root, base)
    result = BaseView.materialize(root, base, temp_root: temp)

    refute File.exists?(temp)
    assert {:env, message} = result
    assert message =~ "a//evil.txt"
  end

  for batch <- [false, true] do
    @tag spec: "ancora.derive.base_reads_batched"
    test "blobs validates the entire listing before any read with batch=#{batch}", %{root: root} do
      base = TmpGitRepo.commit_tree_path!(root, ["a", "..", "evil.txt"], leading_blob: true)
      assert {:ok, entries} = Ancora.Git.ls_tree_entries(root, base)
      assert Enum.map(entries, & &1.path) == ["0-safe.txt", "a/../evil.txt"]
      assert {:ok, ctx} = RunContext.start(root, base, batch: unquote(batch))
      on_exit(fn -> RunContext.stop(ctx) end)

      tracer = start_trace_forwarder(self())
      :erlang.trace(self(), true, [:call, {:tracer, tracer}])
      :erlang.trace_pattern({Ancora.Git, :read_blob, 2}, true, [])

      on_exit(fn ->
        :erlang.trace_pattern({Ancora.Git, :read_blob, 2}, false, [])
        send(tracer, :stop)
      end)

      result = BaseView.blobs(ctx)
      flush_trace(tracer)

      assert collect_calls(Ancora.Git, :read_blob, []) == []
      assert {:env, _} = result

      assert {:ok, %{"0-safe.txt" => "hostile tree payload\n"}} =
               BaseView.blobs(ctx, nil, pathspecs: ["0-safe.txt"])

      flush_trace(tracer)
      assert [[^ctx, _oid]] = collect_calls(Ancora.Git, :read_blob, [])
    end
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize preserves legitimate components containing two dots", %{root: root} do
    TmpGitRepo.write!(root, %{"foo..bar/content.txt" => "legitimate\n"})
    TmpGitRepo.commit!(root, "legitimate path")
    temp = Path.join(root, "base")

    assert {:ok, ^temp} = BaseView.materialize(root, "HEAD", temp_root: temp)
    assert File.read!(Path.join(temp, "foo..bar/content.txt")) == "legitimate\n"
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize rejects a symlink root before writing", %{root: root} do
    # Would fail if BaseView accepted an existing symlink and redirected blob writes.
    TmpGitRepo.write!(root, %{"lib/a.ex" => "blocked\n"})
    TmpGitRepo.commit!(root, "initial")

    target = Path.join(System.tmp_dir!(), "ancora-base-view-target-#{System.unique_integer()}")
    link = target <> "-link"
    File.mkdir!(target)
    File.ln_s!(target, link)

    on_exit(fn ->
      File.rm(link)
      File.rm_rf(target)
    end)

    result = BaseView.materialize(root, "HEAD", temp_root: link)

    assert {result, File.ls!(target)} ==
             {{:error, {:temp_directory, :eexist}}, []}
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "blobs can be narrowed by pathspecs", %{root: root} do
    TmpGitRepo.write!(root, %{"lib/a.ex" => "A\n", "test/a_test.exs" => "T\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, files} = BaseView.blobs(root, "HEAD", pathspecs: ["lib"])
    assert Map.keys(files) == ["lib/a.ex"]
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "materialize writes only requested paths and creates each directory once", %{root: root} do
    TmpGitRepo.write!(root, %{
      ".spec/specs/s.spec.md" => "spec\n",
      "lib/a.ex" => "A\n",
      "lib/b.ex" => "B\n",
      "notes/private.txt" => "skip\n"
    })

    TmpGitRepo.commit!(root, "initial")
    traced = self()
    tracer = start_trace_forwarder(traced)
    :erlang.trace(traced, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({File, :mkdir_p!, 1}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({File, :mkdir_p!, 1}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, temp} = BaseView.materialize(root, "HEAD", pathspecs: [".spec", "lib"])
    on_exit(fn -> File.rm_rf(temp) end)

    files =
      temp
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, temp))
      |> Enum.sort()

    assert files == [".spec/specs/s.spec.md", "lib/a.ex", "lib/b.ex"]

    mkdir_calls = collect_calls(File, :mkdir_p!, [])
    assert Enum.count(mkdir_calls, &(&1 == [Path.join(temp, "lib")])) == 1
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "a repository path requires an explicit base", %{root: root} do
    assert {:error, :base_required} = BaseView.blobs(root)
  end

  defp blob_read_calls(ast) do
    Macro.prewalk(ast, [], fn
      {{:., _, [{:__aliases__, _, [:Git]}, :read_blob]}, _, [_ctx, blob]} = node, acc ->
        {node, [{:read_blob, Macro.to_string(blob)} | acc]}

      {{:., _, [{:__aliases__, _, [:RunContext]}, :start]}, _, args} = node, acc ->
        extra =
          if args |> List.flatten() |> Enum.any?(&match?({:batch, false}, &1)) do
            [:batch_false]
          else
            []
          end

        {node, extra ++ acc}

      {{:., _, [{:__aliases__, _, [:BatchPort]}, name]}, _, _} = node, acc ->
        {node, [{:batch_port, name} | acc]}

      {{:., _, [{:__aliases__, _, [:Ancora, :Git, :BatchPort]}, name]}, _, _} = node, acc ->
        {node, [{:batch_port, name} | acc]}

      other, acc ->
        {other, acc}
    end)
  end

  defp collect_calls(module, function, calls) do
    receive do
      {:forwarded_trace, {:trace, _pid, :call, {^module, ^function, arguments}}} ->
        collect_calls(module, function, [arguments | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  defp flush_trace(tracer) do
    delivered = :erlang.trace_delivered(self())
    assert_receive {:trace_delivered, _, ^delivered}
    send(tracer, {:flush, self(), delivered})
    assert_receive {:flushed, ^delivered}
  end

  defp start_trace_forwarder(parent) do
    spawn(fn -> forward_traces(parent) end)
  end

  defp forward_traces(parent) do
    receive do
      :stop ->
        :ok

      {:flush, caller, ref} ->
        send(caller, {:flushed, ref})
        forward_traces(parent)

      message ->
        send(parent, {:forwarded_trace, message})
        forward_traces(parent)
    end
  end
end
