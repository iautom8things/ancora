defmodule Ancora.Derive.ChangeSet do
  @moduledoc """
  Diff-scoped change set: `git diff --name-status --no-renames -z <base>` union
  `git status --porcelain -z --untracked-files=all`. Base paths resolve to object
  ids before serial blob prefetch through the run's batch port.
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
    with {:ok, output} <- Git.run(root, ["diff", "--name-status", "--no-renames", "-z", base]) do
      parse_name_status(output)
    end
  end

  defp porcelain_status(%RunContext{root: root}) do
    with {:ok, output} <- Git.run(root, ["status", "--porcelain", "-z", "--untracked-files=all"]) do
      parse_porcelain(output)
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

  defp prefetch(%RunContext{}, []), do: {:ok, %{}}

  defp prefetch(%RunContext{root: root, base: base} = ctx, entries) do
    paths = Enum.map(entries, & &1.path)

    with {:ok, tree_entries} <- Git.ls_tree_entries(root, base, paths) do
      oids = Map.new(tree_entries, &{&1.path, &1.oid})

      Enum.reduce_while(entries, {:ok, %{}}, fn %{path: path}, {:ok, acc} ->
        read =
          case Map.fetch(oids, path) do
            {:ok, oid} -> blob_read(Git.read_blob(ctx, {:oid, oid}))
            :error -> :missing
          end

        case read do
          {:error, reason} -> {:halt, {:error, reason}}
          read -> {:cont, {:ok, Map.put(acc, path, read)}}
        end
      end)
    end
  end

  defp blob_read({:ok, payload}) when is_binary(payload), do: {:ok, payload}
  defp blob_read({:error, {:missing_object, _}}), do: :missing
  defp blob_read({:error, {:git, _args, _output, 128}}), do: :missing
  defp blob_read({:error, reason}), do: {:error, reason}

  defp parse_name_status(output) do
    with {:ok, records} <- nul_records(output, :name_status) do
      name_status_entries(records, [])
    end
  end

  defp name_status_entries([], entries), do: {:ok, Enum.reverse(entries)}

  defp name_status_entries([<<code, _::binary>>, old_path, new_path | rest], entries)
       when code in [?R, ?C] do
    with :ok <- validate_path(old_path),
         :ok <- validate_path(new_path) do
      name_status_entries(rest, [
        %{path: new_path, status: :added},
        %{path: old_path, status: :deleted} | entries
      ])
    end
  end

  defp name_status_entries([code, path | rest], entries) do
    with :ok <- validate_path(path) do
      name_status_entries(rest, [%{path: path, status: name_status_code(code)} | entries])
    end
  end

  defp name_status_entries(records, _entries), do: {:error, {:invalid_name_status, records}}

  defp name_status_code(<<"A", _::binary>>), do: :added
  defp name_status_code(<<"D", _::binary>>), do: :deleted
  defp name_status_code(_), do: :modified

  defp parse_porcelain(output) do
    with {:ok, records} <- nul_records(output, :porcelain_status) do
      porcelain_entries(records, [])
    end
  end

  defp porcelain_entries([], entries), do: {:ok, Enum.reverse(entries)}

  defp porcelain_entries([<<"?? ", path::binary>> | rest], entries) do
    with :ok <- validate_path(path) do
      porcelain_entries(rest, [%{path: path, status: :untracked} | entries])
    end
  end

  defp porcelain_entries([<<x, y, " ", new_path::binary>>, old_path | rest], entries)
       when x in [?R, ?C] or y in [?R, ?C] do
    with :ok <- validate_path(old_path),
         :ok <- validate_path(new_path) do
      porcelain_entries(rest, [
        %{path: new_path, status: :added},
        %{path: old_path, status: :deleted} | entries
      ])
    end
  end

  defp porcelain_entries([<<_x, _y, " ", path::binary>> | rest], entries) do
    with :ok <- validate_path(path) do
      porcelain_entries(rest, [%{path: path, status: :modified} | entries])
    end
  end

  defp porcelain_entries(records, _entries), do: {:error, {:invalid_porcelain_status, records}}

  defp nul_records("", _source), do: {:ok, []}

  defp nul_records(output, source) do
    if :binary.last(output) == 0 do
      {:ok, :binary.split(output, <<0>>, [:global, :trim_all])}
    else
      {:error, {:missing_nul_terminator, source}}
    end
  end

  defp validate_path(<<"\"", _::binary>> = path) do
    if String.ends_with?(path, "\"") do
      {:error, {:quoted_git_path, path}}
    else
      :ok
    end
  end

  defp validate_path(_path), do: :ok
end
