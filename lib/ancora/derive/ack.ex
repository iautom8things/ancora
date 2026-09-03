defmodule Ancora.Derive.Ack do
  @moduledoc """
  Detects substantive subject-spec acknowledgment from parsed YAML blocks.

  Only requirement and scenario lists participate. Internal whitespace in
  string values is collapsed before comparison.
  """

  @block_pattern ~r/```([^\n`]*)\n(.*?)\n```/ms
  @keys %{"spec-requirements" => :requirements, "spec-scenarios" => :scenarios}

  @doc "True when requirements or scenarios differ after string normalization."
  @spec substantive?(binary() | nil, binary() | nil) :: boolean()
  def substantive?(base_source, head_source) do
    with {:ok, base} <- parse(base_source),
         {:ok, head} <- parse(head_source) do
      base != head
    else
      _ -> false
    end
  end

  @doc "Alias for `substantive?/2` named for the gate's use."
  @spec acknowledged?(binary() | nil, binary() | nil) :: boolean()
  def acknowledged?(base_source, head_source), do: substantive?(base_source, head_source)

  @doc "Parses and normalizes the acknowledgment-bearing parts of a spec."
  @spec parse(binary() | nil) ::
          {:ok, %{requirements: list(), scenarios: list()}} | {:error, term()}
  def parse(nil), do: {:ok, %{requirements: [], scenarios: []}}

  def parse(source) when is_binary(source) do
    @block_pattern
    |> Regex.scan(source)
    |> Enum.reduce_while({:ok, %{requirements: [], scenarios: []}}, &decode_block/2)
  end

  defp decode_block([_match, info, raw], {:ok, parsed}) do
    case Map.fetch(@keys, spec_tag(info)) do
      {:ok, key} ->
        case YamlElixir.read_from_string(raw) do
          {:ok, entries} when is_list(entries) ->
            {:cont, {:ok, Map.put(parsed, key, normalize(entries))}}

          {:ok, other} ->
            {:halt, {:error, {:invalid_ack_block, key, other}}}

          {:error, reason} ->
            {:halt, {:error, {:invalid_ack_block, key, reason}}}
        end

      :error ->
        {:cont, {:ok, parsed}}
    end
  end

  defp spec_tag(info) do
    info
    |> String.split(~r/\s+/, trim: true)
    |> Enum.find(&Map.has_key?(@keys, &1))
  end

  defp normalize(value) when is_binary(value) do
    value |> String.split() |> Enum.join(" ")
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, normalize(item)} end)
  end

  defp normalize(value), do: value
end
