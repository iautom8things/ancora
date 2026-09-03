defmodule Ancora.Git do
  @moduledoc """
  The only git subprocess spawner in ancora.

  Every git invocation in the library goes through this module. `Ancora.Git.BatchPort`
  is the long-lived `cat-file --batch` reader; `read_blob/2` is the single
  function head for base-side blob reads, with per-file `git show` as the
  escape hatch when the run has no batch port.
  """

  alias Ancora.Derive.RunContext
  alias Ancora.Git.BatchPort

  @type git_error ::
          {:error, :git_executable_not_found}
          | {:error, {:git, [String.t()], String.t(), non_neg_integer()}}

  @doc """
  Runs a git plumbing command against `root`.

  Returns `{:ok, output}` or `{:error, {:git, args, output, status}}`.
  """
  @spec run(Path.t(), [String.t()], keyword()) :: {:ok, String.t()} | git_error()
  def run(root, args, opts \\ []) when is_binary(root) and is_list(args) do
    env = Keyword.get(opts, :env, [])

    case System.find_executable("git") do
      nil ->
        {:error, :git_executable_not_found}

      git ->
        case System.cmd(git, ["-C", root | args], stderr_to_stdout: true, env: env) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {:git, args, output, status}}
        end
    end
  end

  @doc """
  Lists a tree recursively through one `ls-tree -r -z` subprocess.

  Each entry is `%{mode:, type:, oid:, path:}`. Optional `pathspecs` narrow
  the listing. `-z` keeps paths unquoted so names round-trip byte-identical.
  """
  @spec ls_tree_entries(Path.t(), String.t(), [String.t()]) ::
          {:ok, [%{mode: String.t(), type: String.t(), oid: String.t(), path: String.t()}]}
          | git_error()
          | {:error, term()}
  def ls_tree_entries(root, treeish, pathspecs \\ [])

  def ls_tree_entries(root, treeish, pathspecs)
      when is_binary(root) and is_binary(treeish) and is_list(pathspecs) do
    args = ["ls-tree", "-r", "-z", treeish] ++ pathspec_args(pathspecs)

    with {:ok, listing} <- run(root, args) do
      parse_ls_tree(listing)
    end
  end

  @doc """
  Reads one base-side blob.

  When the run context owns a `BatchPort`, the read goes through that port.
  When it does not, the same function head falls back to `git show <base>:<path>`.
  """
  @spec read_blob(RunContext.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read_blob(%RunContext{batch_port: %BatchPort{} = port, base: base}, path)
      when is_binary(path) do
    case BatchPort.fetch(port, blob_spec(base, path)) do
      {:ok, %{payload: payload}} -> {:ok, payload}
      {:error, _} = error -> error
    end
  end

  def read_blob(%RunContext{batch_port: nil, root: root, base: base}, path)
      when is_binary(path) do
    run(root, ["show", blob_spec(base, path)])
  end

  @doc false
  @spec blob_spec(String.t(), String.t()) :: String.t()
  def blob_spec(base, path), do: "#{base}:#{path}"

  defp pathspec_args([]), do: []
  defp pathspec_args(pathspecs), do: ["--" | pathspecs]

  defp parse_ls_tree(listing) do
    listing
    |> :binary.split(<<0>>, [:global, :trim_all])
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      with [meta, path] <- :binary.split(record, "\t"),
           [mode, type, oid] <- String.split(meta, " ", parts: 3) do
        {:cont, {:ok, [%{mode: mode, type: type, oid: oid, path: path} | acc]}}
      else
        _ -> {:halt, {:error, {:unexpected_tree_entry, record}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
