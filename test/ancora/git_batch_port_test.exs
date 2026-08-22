Code.require_file("../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.Git.BatchPortTest do
  use ExUnit.Case, async: true

  alias Ancora.Git.BatchPort
  alias Ancora.TmpGitRepo

  @tag spec: "ancora.derive.base_reads_batched"
  test "parse_stream returns three payloads including a zero-size blob" do
    # Would fail if the frame parser dropped the empty blob or consumed the
    # following header as payload, so later base files would be attributed
    # to the wrong path.
    oid1 = String.duplicate("a", 40)
    oid2 = String.duplicate("b", 40)
    oid3 = String.duplicate("c", 40)

    stream =
      oid1 <>
        " blob 5\nhello\n" <>
        oid2 <>
        " blob 0\n\n" <>
        oid3 <>
        " blob 3\nbye\n"

    assert {:ok, [one, two, three], ""} = BatchPort.parse_stream(stream)
    assert one == %{oid: oid1, type: "blob", size: 5, payload: "hello"}
    assert two == %{oid: oid2, type: "blob", size: 0, payload: ""}
    assert three == %{oid: oid3, type: "blob", size: 3, payload: "bye"}
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "parse_stream keeps a trailing incomplete frame in rest" do
    oid = String.duplicate("d", 40)
    stream = oid <> " blob 4\nab"

    assert {:ok, [], ^stream} = BatchPort.parse_stream(stream)
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "batch port is spawned without stderr_to_stdout" do
    # Would fail if Port.open merged git stderr into stdout, so git chatter
    # could interleave with blob payloads and corrupt every subsequent frame.
    assert :stderr_to_stdout not in BatchPort.port_opts()

    source = File.read!(Path.expand("lib/ancora/git/batch_port.ex"))
    {:ok, ast} = Code.string_to_quoted(source)

    opens =
      ast
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, [:Port]}, :open]}, _, args} = node, acc ->
          {node, [Macro.to_string(args) | acc]}

        other, acc ->
          {other, acc}
      end)
      |> elem(1)

    assert opens != []

    Enum.each(opens, fn printed ->
      refute printed =~ "stderr_to_stdout"
    end)
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "fetch returns payloads in request order through one port" do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)

    contents = [
      "",
      "line1\nline2\n\nline4\n",
      "#{String.duplicate("a", 40)} blob 12\nnot-a-header\n",
      "tail"
    ]

    TmpGitRepo.write!(root, %{"README.md" => "seed\n"})
    TmpGitRepo.commit!(root, "seed")

    blobs =
      Enum.map(contents, fn content ->
        path = Path.join(root, "blob.tmp")
        File.write!(path, content)
        oid = root |> TmpGitRepo.git!(["hash-object", "-w", path]) |> String.trim()
        File.rm!(path)
        oid
      end)

    assert {:ok, port} = BatchPort.open(root)
    on_exit(fn -> BatchPort.close(port) end)

    read =
      Enum.map(blobs, fn oid ->
        assert {:ok, record} = BatchPort.fetch(port, oid)
        assert record.size == byte_size(record.payload)
        record.payload
      end)

    assert read == contents
  end

  @tag spec: "ancora.derive.base_reads_batched"
  test "fetch of a missing object does not corrupt the next blob" do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)
    TmpGitRepo.write!(root, %{"lib/a.ex" => "keep\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, port} = BatchPort.open(root)
    on_exit(fn -> BatchPort.close(port) end)

    absent = "HEAD:no-such-file.ex"
    assert {:error, {:missing_object, ^absent}} = BatchPort.fetch(port, absent)
    assert {:ok, %{payload: "keep\n"}} = BatchPort.fetch(port, "HEAD:lib/a.ex")
  end
end
