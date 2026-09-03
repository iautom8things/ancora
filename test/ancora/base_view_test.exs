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

  defp start_trace_forwarder(parent) do
    spawn(fn -> forward_traces(parent) end)
  end

  defp forward_traces(parent) do
    receive do
      :stop ->
        :ok

      message ->
        send(parent, {:forwarded_trace, message})
        forward_traces(parent)
    end
  end
end
