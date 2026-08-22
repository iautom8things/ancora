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
  test "blobs reads the base tree through Git.read_blob/2", %{root: root} do
    # Would fail if BaseView called BatchPort.fetch or opened an ephemeral
    # port instead of Git.read_blob/2.
    source = File.read!(Path.expand("lib/ancora/base_view.ex"))
    {:ok, ast} = Code.string_to_quoted(source)
    {_, calls} = blob_read_calls(ast)
    assert :read_blob in calls
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

  defp blob_read_calls(ast) do
    Macro.prewalk(ast, [], fn
      {{:., _, [{:__aliases__, _, [:Git]}, :read_blob]}, _, _} = node, acc ->
        {node, [:read_blob | acc]}

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
end
