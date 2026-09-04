defmodule Ancora.Derive.RunContext do
  @moduledoc """
  Per-run detector context for the git batch port.

  The context is passed by reference. Nothing here is named, registered, or
  written to disk.
  """

  alias Ancora.Git.BatchPort

  @enforce_keys [:root, :base]
  defstruct [:root, :base, :batch_port]

  @type t :: %__MODULE__{
          root: Path.t(),
          base: String.t(),
          batch_port: BatchPort.t() | nil
        }

  @doc """
  Opens one unregistered `git cat-file --batch` port against `root` unless
  `batch: false`.
  """
  @spec start(Path.t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(root, base, opts \\ []) when is_binary(root) and is_binary(base) do
    case open_batch_port(root, opts) do
      {:ok, batch_port} ->
        {:ok,
         %__MODULE__{
           root: Path.expand(root),
           base: base,
           batch_port: batch_port
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Closes the batch port."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{batch_port: batch_port}) do
    BatchPort.close(batch_port)
  end

  defp open_batch_port(root, opts) do
    if Keyword.get(opts, :batch, true) do
      BatchPort.open(root)
    else
      {:ok, nil}
    end
  end
end
