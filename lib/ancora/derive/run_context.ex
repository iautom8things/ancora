defmodule Ancora.Derive.RunContext do
  @moduledoc """
  Per-run detector context: an unnamed ETS memo table and the git batch port,
  both passed by reference. Nothing here is named, registered, or written to disk.
  """

  alias Ancora.Git.BatchPort

  @enforce_keys [:root, :base, :memo]
  defstruct [:root, :base, :memo, :batch_port]

  @type kind :: :def_index | :resolver | :ast | :blob | :module_map | :ambient
  @type t :: %__MODULE__{
          root: Path.t(),
          base: String.t(),
          memo: :ets.tid(),
          batch_port: BatchPort.t() | nil
        }

  @kind_rank %{def_index: 4, resolver: 3, module_map: 2, ambient: 2, blob: 1, ast: 0}

  @doc """
  Opens an unnamed public ETS memo table and, unless `batch: false`, one
  unregistered `git cat-file --batch` port against `root`.
  """
  @spec start(Path.t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(root, base, opts \\ []) when is_binary(root) and is_binary(base) do
    memo = :ets.new(__MODULE__, [:set, :public])

    case open_batch_port(root, opts) do
      {:ok, batch_port} ->
        {:ok,
         %__MODULE__{
           root: Path.expand(root),
           base: base,
           memo: memo,
           batch_port: batch_port
         }}

      {:error, reason} ->
        :ets.delete(memo)
        {:error, reason}
    end
  end

  @doc "Closes the batch port and deletes the memo table."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{memo: memo, batch_port: batch_port}) do
    BatchPort.close(batch_port)

    if :ets.info(memo) != :undefined do
      :ets.delete(memo)
    end

    :ok
  end

  @doc """
  Stores `value` under `key` at `kind`.

  DefIndex and resolver results outrank a raw AST for the same key: a lower-ranked
  kind does not overwrite a higher-ranked entry.
  """
  @spec memo_put(t(), term(), term(), kind()) :: :ok
  def memo_put(%__MODULE__{memo: memo}, key, value, kind \\ :ast) do
    case :ets.lookup(memo, key) do
      [{^key, {existing_kind, _stored}}] ->
        if rank(kind) < rank(existing_kind) do
          :ok
        else
          true = :ets.insert(memo, {key, {kind, value}})
          :ok
        end

      _ ->
        true = :ets.insert(memo, {key, {kind, value}})
        :ok
    end
  end

  @doc "Looks up a memo entry. Returns `{:ok, value, kind}` or `:error`."
  @spec memo_get(t(), term()) :: {:ok, term(), kind()} | :error
  def memo_get(%__MODULE__{memo: memo}, key) do
    case :ets.lookup(memo, key) do
      [{^key, {kind, value}}] -> {:ok, value, kind}
      [] -> :error
    end
  end

  defp open_batch_port(root, opts) do
    if Keyword.get(opts, :batch, true) do
      BatchPort.open(root)
    else
      {:ok, nil}
    end
  end

  defp rank(kind), do: Map.fetch!(@kind_rank, kind)
end
