defmodule Ancora.BaseView do
  @moduledoc """
  Materializes a git ref's blobs via `ls-tree` and `Ancora.Git.read_blob/2`.
  Parsing of those files is a later stage's job.

  Ported from SpecLedEx.BaseView; git plumbing lives in `Ancora.Git`.
  """

  alias Ancora.Derive.RunContext
  alias Ancora.Git

  @doc """
  Reads every blob under `base` (optionally narrowed by `:pathspecs`) into a
  `%{path => content}` map.

  Every blob goes through `Git.read_blob/2`: the run's batch port when present,
  otherwise per-file `git show`. A repo path (no run context) does not open an
  ephemeral batch port.
  """
  @spec blobs(RunContext.t() | Path.t(), String.t() | nil, keyword()) ::
          {:ok, %{String.t() => binary()}} | {:error, term()}
  def blobs(source, base \\ nil, opts \\ [])

  def blobs(%RunContext{} = ctx, base, opts) do
    ctx = %{ctx | base: base || ctx.base}
    pathspecs = Keyword.get(opts, :pathspecs, [])
    read_tree_blobs(ctx, pathspecs)
  end

  def blobs(root, base, opts) when is_binary(root) and is_binary(base) do
    with {:ok, ctx} <- RunContext.start(root, base, batch: false) do
      try do
        blobs(ctx, base, opts)
      after
        RunContext.stop(ctx)
      end
    end
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

  defp read_tree_blobs(%RunContext{} = ctx, pathspecs) do
    with {:ok, entries} <- Git.ls_tree_entries(ctx.root, ctx.base, pathspecs) do
      entries
      |> Enum.filter(&(&1.type == "blob"))
      |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
        case Git.read_blob(ctx, entry.path) do
          {:ok, payload} ->
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
