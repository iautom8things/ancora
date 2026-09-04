Code.require_file("../support/tmp_git_repo.exs", __DIR__)

defmodule Ancora.Git.BatchPortTest do
  use ExUnit.Case, async: false

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
    # Would fail if `:stderr_to_stdout` were in the options list spliced into
    # `:erlang.open_port/2` in `BatchPort.open/1` (after `@port_opts` expands).
    # Source-AST prints of `| @port_opts` would still pass if the attribute
    # included that flag; this walk reads the compiled call-site list.
    opts_lists = open_port_option_lists()
    assert opts_lists != []

    Enum.each(opts_lists, fn opts ->
      assert :binary in opts
      assert :exit_status in opts
      assert :hide in opts
      refute :stderr_to_stdout in opts
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

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "a timed out fetch poisons the port before another request can read stale data" do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)

    payload = String.duplicate("x", 4_000_000)
    TmpGitRepo.write!(root, %{"large.bin" => payload, "small.txt" => "fresh\n"})
    TmpGitRepo.commit!(root, "initial")

    assert {:ok, port} = BatchPort.open(root)
    on_exit(fn -> BatchPort.close(port) end)

    assert {:error, :cat_file_batch_timeout} =
             BatchPort.fetch(port, "HEAD:large.bin", timeout: 0)

    assert {:error, :port_poisoned} = BatchPort.fetch(port, "HEAD:small.txt")
    assert Port.info(port.port) == nil
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "open returns data when git is absent from PATH" do
    root = TmpGitRepo.create!()
    on_exit(fn -> TmpGitRepo.cleanup!(root) end)

    original_path = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", original_path) end)
    System.put_env("PATH", Path.join(root, "no-executables"))

    assert {:error, :git_executable_not_found} = BatchPort.open(root)
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "fetch converts a Port.command error into a closed poisoned port" do
    source = BatchPort |> compiled_definition!(:fetch, 3) |> Macro.to_string()

    assert source =~ "rescue"
    assert source =~ "[ArgumentError]"
    assert source =~ "{:close"
    assert source =~ "{:error, :port_poisoned}"
  end

  defp open_port_option_lists do
    path = :code.which(BatchPort)

    {:ok, {_, [{:debug_info, {:debug_info_v1, :elixir_erl, {:elixir_v1, map, _}}}]}} =
      :beam_lib.chunks(path, [:debug_info])

    {{:open, 1}, :def, _meta, clauses} =
      Enum.find(map.definitions, fn {{name, arity}, _, _, _} ->
        {name, arity} == {:open, 1}
      end)

    Enum.flat_map(clauses, fn {_meta, _args, _guards, body} ->
      collect_open_port_opts(body)
    end)
  end

  defp compiled_definition!(module, name, arity) do
    path = :code.which(module)

    {:ok, {_, [{:debug_info, {:debug_info_v1, :elixir_erl, {:elixir_v1, map, _}}}]}} =
      :beam_lib.chunks(path, [:debug_info])

    {{^name, ^arity}, _kind, _meta, clauses} =
      Enum.find(map.definitions, fn {{defined_name, defined_arity}, _, _, _} ->
        {defined_name, defined_arity} == {name, arity}
      end)

    clauses
  end

  defp collect_open_port_opts(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [:erlang, :open_port]}, _, [_name, opts_ast]} = node, acc ->
          {node, [expand_option_names(opts_ast) | acc]}

        {{:., _, [{:__aliases__, _, [:Port]}, :open]}, _, [_name, opts_ast]} = node, acc ->
          {node, [expand_option_names(opts_ast) | acc]}

        other, acc ->
          {other, acc}
      end)

    acc
  end

  defp expand_option_names(opts_ast) do
    opts_ast
    |> expand_cons()
    |> Enum.map(&option_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp expand_cons({:|, _, [head, tail]}), do: [head | expand_cons(tail)]

  defp expand_cons(list) when is_list(list) do
    Enum.flat_map(list, fn
      {:|, _, [head, tail]} -> [head | expand_cons(tail)]
      item -> [item]
    end)
  end

  defp expand_cons(other), do: [other]

  defp option_name(atom) when is_atom(atom), do: atom
  defp option_name({atom, _value}) when is_atom(atom), do: atom
  defp option_name(_), do: nil
end
