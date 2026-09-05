defmodule Ancora.BaseView do
  @moduledoc """
  Materializes a git ref's blobs via `ls-tree` and `Ancora.Git.read_blob/2`.
  Parsing of those files is a later stage's job.

  Ported from SpecLedEx.BaseView; git plumbing lives in `Ancora.Git`.
  """

  alias Ancora.Derive.RunContext
  alias Ancora.Git
  alias Ancora.TempName

  @doc """
  Reads every blob under `base` (optionally narrowed by `:pathspecs`) into a
  `%{path => content}` map.

  Every blob goes through `Git.read_blob/2`: the run's batch port when present,
  otherwise per-file `git show`. A repo path (no run context) does not open an
  ephemeral batch port.
  """
  @spec blobs(RunContext.t() | Path.t(), String.t() | nil, keyword()) ::
          {:ok, %{String.t() => binary()}} | {:error, term()} | {:env, String.t()}
  def blobs(source, base \\ nil, opts \\ [])

  def blobs(%RunContext{} = ctx, base, opts) do
    ctx = %{ctx | base: base || ctx.base}
    pathspecs = Keyword.get(opts, :pathspecs, [])
    read_tree_blobs(ctx, pathspecs)
  end

  def blobs(root, nil, _opts) when is_binary(root), do: {:error, :base_required}

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

  The caller owns cleanup. `:temp_root` overrides the generated root for
  controlled collision checks.
  """
  @spec materialize(RunContext.t() | Path.t(), String.t() | nil, keyword()) ::
          {:ok, Path.t()} | {:error, term()} | {:env, String.t()}
  def materialize(source, base \\ nil, opts \\ []) do
    with {:ok, files} <- blobs(source, base, opts) do
      temp_root = Keyword.get(opts, :temp_root) || unique_temp()

      case File.mkdir(temp_root) do
        :ok ->
          files
          |> Enum.group_by(fn {path, _content} ->
            temp_root |> Path.join(path) |> Path.dirname()
          end)
          |> Enum.each(fn {directory, directory_files} ->
            File.mkdir_p!(directory)

            Enum.each(directory_files, fn {path, content} ->
              File.write!(Path.join(temp_root, path), content)
            end)
          end)

          {:ok, temp_root}

        {:error, reason} ->
          {:error, {:temp_directory, reason}}
      end
    end
  end

  defp read_tree_blobs(%RunContext{} = ctx, pathspecs) do
    with {:ok, entries} <- Git.ls_tree_entries(ctx.root, ctx.base, pathspecs),
         :ok <- validate_tree_paths(entries) do
      entries
      |> Enum.filter(&(&1.type == "blob"))
      |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
        case Git.read_blob(ctx, entry.oid) do
          {:ok, payload} ->
            {:cont, {:ok, Map.put(acc, entry.path, payload)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_tree_paths(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      components = :binary.split(entry.path, "/", [:global])

      if Enum.any?(components, &(&1 in ["..", ".", ""])) do
        {:halt, {:env, "unsafe base tree path: #{inspect(entry.path)}"}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp unique_temp do
    Path.join(System.tmp_dir!(), "ancora_base_view_#{TempName.cross_vm_suffix()}")
  end
end
