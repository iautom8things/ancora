defmodule Ancora.Derive.ChangeSet do
  @moduledoc """
  Diff-scoped change set: `git diff --name-status --no-renames <base>` union
  `git status --porcelain --untracked-files=all`, with serial base-blob prefetch
  through the run's batch port.
  """

  alias Ancora.Derive.RunContext
  alias Ancora.Git

  @type status :: :added | :deleted | :modified | :untracked
  @type entry :: %{path: String.t(), status: status()}
  @type blob_read :: {:ok, binary()} | :missing

  defstruct entries: [], prefetched: %{}, path_set: MapSet.new()

  @type t :: %__MODULE__{
          entries: [entry()],
          prefetched: %{String.t() => blob_read()},
          path_set: MapSet.t(String.t())
        }

  @doc """
  Computes the change set against `ctx.base` and prefetches every path's base
  blob serially through the run's batch port (or `git show` when no port is set).
  """
  @spec compute(RunContext.t()) :: {:ok, t()} | {:error, term()}
  def compute(%RunContext{} = ctx) do
    with {:ok, diff_entries} <- name_status(ctx),
         {:ok, status_entries} <- porcelain_status(ctx) do
      entries = union(diff_entries, status_entries)

      case prefetch(ctx, entries) do
        {:ok, prefetched} ->
          {:ok,
           %__MODULE__{
             entries: entries,
             prefetched: prefetched,
             path_set: entries |> Enum.map(& &1.path) |> MapSet.new()
           }}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc "Paths in the change set, in entry order."
  @spec paths(t()) :: [String.t()]
  def paths(%__MODULE__{entries: entries}), do: Enum.map(entries, & &1.path)

  @doc "Returns whether `path` belongs to the change set's precomputed path set."
  @spec changed_path?(t(), String.t()) :: boolean()
  def changed_path?(%__MODULE__{path_set: path_set}, path), do: MapSet.member?(path_set, path)

  defp name_status(%RunContext{root: root, base: base}) do
    with {:ok, output} <- Git.run(root, ["diff", "--name-status", "--no-renames", base]) do
      {:ok, parse_name_status(output)}
    end
  end

  defp porcelain_status(%RunContext{root: root}) do
    with {:ok, output} <- Git.run(root, ["status", "--porcelain", "--untracked-files=all"]) do
      {:ok, parse_porcelain(output)}
    end
  end

  defp union(diff_entries, status_entries) do
    by_path = Map.new(diff_entries, &{&1.path, &1})

    merged =
      Enum.reduce(status_entries, by_path, fn entry, acc ->
        Map.put_new(acc, entry.path, entry)
      end)

    merged
    |> Map.values()
    |> Enum.sort_by(& &1.path)
  end

  defp prefetch(%RunContext{} = ctx, entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn %{path: path}, {:ok, acc} ->
      case blob_read(Git.read_blob(ctx, path)) do
        {:error, reason} -> {:halt, {:error, reason}}
        read -> {:cont, {:ok, Map.put(acc, path, read)}}
      end
    end)
  end

  defp blob_read({:ok, payload}) when is_binary(payload), do: {:ok, payload}
  defp blob_read({:error, {:missing_object, _}}), do: :missing
  defp blob_read({:error, {:git, _args, _output, 128}}), do: :missing
  defp blob_read({:error, reason}), do: {:error, reason}

  defp parse_name_status(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&name_status_entry/1)
  end

  defp name_status_entry(line) do
    case String.split(line, "\t") do
      [code, path] ->
        [%{path: path, status: name_status_code(code)}]

      [code, old_path, new_path] ->
        # R/C rows if a git version ignores --no-renames: treat as D+A.
        _ = code
        [%{path: old_path, status: :deleted}, %{path: new_path, status: :added}]

      _ ->
        []
    end
  end

  defp name_status_code(<<"A", _::binary>>), do: :added
  defp name_status_code(<<"D", _::binary>>), do: :deleted
  defp name_status_code(_), do: :modified

  defp parse_porcelain(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&porcelain_entry/1)
  end

  defp porcelain_entry(<<"?? ", path::binary>>), do: [%{path: path, status: :untracked}]

  defp porcelain_entry(<<_x::binary-size(1), _y::binary-size(1), " ", rest::binary>>) do
    porcelain_xy(rest)
  end

  defp porcelain_entry(_), do: []

  defp porcelain_xy(rest) do
    case String.split(rest, " -> ", parts: 2) do
      [old_path, new_path] ->
        [%{path: old_path, status: :deleted}, %{path: new_path, status: :added}]

      [path] ->
        [%{path: path, status: porcelain_path_status(path)}]
    end
  end

  # Tracked porcelain rows that were not already in name-status (rare; union
  # prefers name-status) are treated as modified.
  defp porcelain_path_status(_path), do: :modified
end
