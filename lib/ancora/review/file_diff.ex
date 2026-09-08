defmodule Ancora.Review.FileDiff do
  @moduledoc false

  alias Ancora.Git

  @type line_kind :: :file_header | :hunk_header | :add | :del | :ctx
  @type line :: {line_kind(), String.t()}

  @spec for_files(Path.t(), String.t(), [Path.t()]) :: %{Path.t() => [line()]}
  def for_files(_root, _base, []), do: %{}

  def for_files(root, base, paths) do
    {tracked, untracked} = partition_tracked(root, paths)

    tracked_diffs =
      case tracked do
        [] -> %{}
        files -> files |> diff(root, base) |> parse(files)
      end

    additions = Map.new(untracked, &{&1, untracked_addition(root, &1)})
    Map.merge(tracked_diffs, additions)
  end

  defp diff(paths, root, base) do
    case Git.run(root, [
           "-c",
           "core.quotePath=false",
           "diff",
           "--no-color",
           "--relative",
           "--no-renames",
           "--src-prefix=a/",
           "--dst-prefix=b/",
           "--no-ext-diff",
           "--no-textconv",
           base,
           "--" | paths
         ]) do
      {:ok, output} -> sanitize(output)
      {:error, _reason} -> ""
    end
  end

  defp partition_tracked(root, paths) do
    untracked =
      case Git.run(root, ["ls-files", "-z", "--others", "--exclude-standard", "--" | paths]) do
        {:ok, output} -> output |> String.split(<<0>>, trim: true) |> MapSet.new()
        {:error, _reason} -> MapSet.new()
      end

    Enum.split_with(paths, &(not MapSet.member?(untracked, &1)))
  end

  defp untracked_addition(root, path) do
    case File.read(Path.join(root, path)) do
      {:ok, content} when is_binary(content) ->
        if String.valid?(content) do
          [{:file_header, "diff --git a/#{path} b/#{path}"}] ++
            Enum.map(String.split(content, "\n"), &{:add, "+" <> &1})
        else
          [{:ctx, "Binary file (#{byte_size(content)} bytes) not shown"}]
        end

      {:error, _reason} ->
        []
    end
  end

  defp sanitize(binary) do
    if String.valid?(binary) do
      binary
    else
      binary
      |> String.chunk(:valid)
      |> Enum.map_join(fn chunk ->
        if String.valid?(chunk), do: chunk, else: String.duplicate("�", byte_size(chunk))
      end)
    end
  end

  defp parse("", _paths), do: %{}

  defp parse(text, paths) do
    headers =
      Map.new(paths, fn path ->
        {"diff --git #{quote_path("a/" <> path)} #{quote_path("b/" <> path)}", path}
      end)

    text
    |> String.split("\n")
    |> Enum.reduce({nil, %{}, []}, fn line, {current, diffs, lines} = state ->
      case Map.fetch(headers, line) do
        {:ok, path} -> {path, stash(current, diffs, lines), [{:file_header, line}]}
        :error -> consume(line, state)
      end
    end)
    |> finish()
  end

  defp quote_path(path) do
    escapes = %{
      7 => "\\a",
      8 => "\\b",
      9 => "\\t",
      10 => "\\n",
      11 => "\\v",
      12 => "\\f",
      13 => "\\r",
      34 => "\\\"",
      92 => "\\\\"
    }

    escaped =
      for <<byte <- path>>, into: "" do
        cond do
          Map.has_key?(escapes, byte) ->
            Map.fetch!(escapes, byte)

          byte < 32 or byte == 127 ->
            "\\" <> String.pad_leading(Integer.to_string(byte, 8), 3, "0")

          true ->
            <<byte>>
        end
      end

    if escaped == path, do: path, else: "\"" <> escaped <> "\""
  end

  defp consume("@@ " <> _rest = line, {path, diffs, lines}),
    do: {path, diffs, [{:hunk_header, line} | lines]}

  defp consume("+++" <> _rest = line, state), do: add(state, :file_header, line)
  defp consume("---" <> _rest = line, state), do: add(state, :file_header, line)
  defp consume("+" <> _rest = line, state), do: add(state, :add, line)
  defp consume("-" <> _rest = line, state), do: add(state, :del, line)
  defp consume("\\ " <> _rest = line, state), do: add(state, :ctx, line)

  defp consume(line, state) do
    kind = if metadata?(line), do: :file_header, else: :ctx
    add(state, kind, line)
  end

  defp add({path, diffs, lines}, kind, line), do: {path, diffs, [{kind, line} | lines]}

  defp metadata?(line) do
    Enum.any?(
      [
        "index ",
        "new file ",
        "deleted file ",
        "old mode ",
        "new mode ",
        "similarity ",
        "rename ",
        "copy ",
        "Binary files "
      ],
      &String.starts_with?(line, &1)
    )
  end

  defp finish({current, diffs, lines}), do: stash(current, diffs, lines)
  defp stash(nil, diffs, _lines), do: diffs
  defp stash(path, diffs, lines), do: Map.put(diffs, path, Enum.reverse(lines))
end
