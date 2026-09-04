defmodule Ancora.Git.BatchPort do
  @moduledoc """
  One `git cat-file --batch` port per run.

  The port is owned by `Ancora.Derive.RunContext`, never registered, and is
  spawned without `:stderr_to_stdout` so git stderr cannot interleave with
  blob payloads. Framing is `<oid> <type> <size>\\n<payload>\\n`.
  """

  defstruct [:port, :root]

  @type t :: %__MODULE__{port: port(), root: Path.t()}

  @type record :: %{
          oid: String.t(),
          type: String.t(),
          size: non_neg_integer(),
          payload: binary()
        }

  @port_opts [:binary, :exit_status, :hide]
  @default_timeout 60_000

  @doc """
  Opens an unregistered `git cat-file --batch` port against `root`.
  """
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(root) when is_binary(root) do
    case System.find_executable("git") do
      nil ->
        {:error, :git_executable_not_found}

      git ->
        port =
          Port.open({:spawn_executable, git}, [
            {:args, ["-C", root, "cat-file", "--batch"]} | @port_opts
          ])

        {:ok, %__MODULE__{port: port, root: root}}
    end
  end

  @doc """
  Requests one object (`<oid>` or `<rev>:<path>`) and waits for its frame.
  """
  @spec fetch(t(), String.t(), keyword()) ::
          {:ok, record()} | {:error, term()}
  def fetch(%__MODULE__{port: port}, spec, opts \\ []) when is_binary(spec) do
    if Port.info(port) == nil do
      {:error, :port_poisoned}
    else
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      try do
        true = Port.command(port, [spec, "\n"])

        case collect_one(port, <<>>, timeout) do
          {:error, {:missing_object, ^spec}} = error ->
            error

          {:error, _reason} = error ->
            close(port)
            error

          result ->
            result
        end
      rescue
        ArgumentError ->
          close(port)
          {:error, :port_poisoned}
      end
    end
  end

  @doc """
  Fetches each spec serially through the port, in request order.
  """
  @spec prefetch(t(), [String.t()], keyword()) :: [
          {String.t(), {:ok, record()} | {:error, term()}}
        ]
  def prefetch(%__MODULE__{} = batch, specs, opts \\ []) when is_list(specs) do
    Enum.map(specs, fn spec -> {spec, fetch(batch, spec, opts)} end)
  end

  @doc """
  Parses a captured `git cat-file --batch` byte stream into complete records.

  Returns `{:ok, records, rest}` where `rest` is any trailing incomplete bytes.
  """
  @spec parse_stream(binary()) ::
          {:ok, [record() | {:missing, String.t()}], binary()} | {:error, term()}
  def parse_stream(buffer) when is_binary(buffer) do
    parse_stream(buffer, [])
  end

  @doc "Closes the port and drains leftover messages."
  @spec close(t() | port() | nil) :: :ok
  def close(nil), do: :ok

  def close(%__MODULE__{port: port}), do: close(port)

  def close(port) when is_port(port) do
    ref = :erlang.monitor(:port, port)

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    receive do
      {:DOWN, ^ref, :port, ^port, _reason} -> :ok
    after
      500 -> :ok
    end

    :erlang.demonitor(ref, [:flush])
    drain_port_messages(port)
  end

  defp parse_stream(buffer, acc) do
    case parse_record(buffer) do
      {:blob, record, rest} ->
        parse_stream(rest, [record | acc])

      {:missing, id, rest} ->
        parse_stream(rest, [{:missing, id} | acc])

      :incomplete ->
        {:ok, Enum.reverse(acc), buffer}

      {:bad_header, header} ->
        {:error, {:cat_file_batch_bad_header, header}}
    end
  end

  defp collect_one(port, buffer, timeout) do
    case parse_record(buffer) do
      {:blob, record, _rest} ->
        {:ok, record}

      {:missing, id, _rest} ->
        {:error, {:missing_object, id}}

      {:bad_header, header} ->
        {:error, {:cat_file_batch_bad_header, header}}

      :incomplete ->
        receive do
          {^port, {:data, data}} ->
            collect_one(port, buffer <> data, timeout)

          {^port, {:exit_status, status}} ->
            {:error, {:cat_file_batch_exited, status}}
        after
          timeout -> {:error, :cat_file_batch_timeout}
        end
    end
  end

  # `cat-file --batch` answers each request with either
  # `<oid> <type> <size>\n<contents>\n` or `<id> missing\n`.
  defp parse_record(buffer) do
    case :binary.split(buffer, "\n") do
      [_incomplete_header] ->
        :incomplete

      [header, rest] ->
        case missing_id(header) do
          {:ok, id} ->
            {:missing, id, rest}

          :error ->
            case String.split(header, " ") do
              [oid, type, size] ->
                case Integer.parse(size) do
                  {bytes, ""} -> parse_payload(oid, type, bytes, header, rest)
                  _ -> {:bad_header, header}
                end

              _ ->
                {:bad_header, header}
            end
        end
    end
  end

  defp missing_id(header) when byte_size(header) > byte_size(" missing") do
    suffix_size = byte_size(" missing")
    id_size = byte_size(header) - suffix_size

    case header do
      <<id::binary-size(id_size), " missing">> -> {:ok, id}
      _ -> :error
    end
  end

  defp missing_id(_header), do: :error

  defp parse_payload(oid, type, bytes, header, rest) do
    case rest do
      <<content::binary-size(bytes), "\n", tail::binary>> ->
        {:blob, %{oid: oid, type: type, size: bytes, payload: content}, tail}

      _ when byte_size(rest) <= bytes ->
        :incomplete

      _ ->
        {:bad_header, header}
    end
  end

  defp drain_port_messages(port) do
    receive do
      {^port, _message} -> drain_port_messages(port)
    after
      0 -> :ok
    end
  end
end
