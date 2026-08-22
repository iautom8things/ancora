defmodule Ancora.BaseView do
  @moduledoc """
  Materializes a git ref's blobs via `ls-tree` and the run's `cat-file --batch`
  port. Parsing of those files is a later stage's job.

  Ported from SpecLedEx.BaseView; git plumbing lives in `Ancora.Git`.
  """

  alias Ancora.Derive.RunContext
  alias Ancora.Git
  alias Ancora.Git.BatchPort

  @doc """
  Reads every blob under `base` (optionally narrowed by `:pathspecs`) into a
  `%{path => content}` map.
  """
  @spec blobs(RunContext.t() | Path.t(), String.t() | nil, keyword()) ::
          {:ok, %{String.t() => binary()}} | {:error, term()}
  def blobs(source, base \\ nil, opts \\ [])

  def blobs(%RunContext{} = ctx, base, opts) do
    base = base || ctx.base
    pathspecs = Keyword.get(opts, :pathspecs, [])
    with_port(ctx, fn root, port -> read_tree_blobs(root, port, base, pathspecs) end)
  end

  def blobs(root, base, opts) when is_binary(root) and is_binary(base) do
    pathspecs = Keyword.get(opts, :pathspecs, [])
    with_port(root, fn expanded, port -> read_tree_blobs(expanded, port, base, pathspecs) end)
  end

  @doc """
  Writes `blobs/3` into an isolated temp workspace and returns its path.

  The caller owns cleanup.
  """
  @spec materialize(RunContext.t() | Path.t(), String.t() | nil, keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def materialize(source, base \\ nil, opts \\ []) do
    with {:ok, files} <- blobs(source, base, opts) do
      temp_root = unique_temp()
      File.mkdir_p!(temp_root)

      Enum.each(files, fn {path, content} ->
        destination = Path.join(temp_root, path)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, content)
      end)

      {:ok, temp_root}
    end
  end

  defp with_port(%RunContext{batch_port: %BatchPort{} = port, root: root}, fun) do
    fun.(root, port)
  end

  defp with_port(%RunContext{root: root}, fun) do
    with_open_port(root, fun)
  end

  defp with_port(root, fun) when is_binary(root) do
    with_open_port(root, fun)
  end

  defp with_open_port(root, fun) do
    with {:ok, port} <- BatchPort.open(root) do
      try do
        fun.(root, port)
      after
        BatchPort.close(port)
      end
    end
  end

  defp read_tree_blobs(root, port, base, pathspecs) do
    with {:ok, entries} <- Git.ls_tree_entries(root, base, pathspecs) do
      entries
      |> Enum.filter(&(&1.type == "blob"))
      |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
        case BatchPort.fetch(port, entry.oid) do
          {:ok, %{payload: payload}} ->
            {:cont, {:ok, Map.put(acc, entry.path, payload)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp unique_temp do
    Path.join(
      System.tmp_dir!(),
      "ancora_base_view_#{System.pid()}_#{System.unique_integer([:positive])}"
    )
  end
end
