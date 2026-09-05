defmodule Ancora.SourceScan do
  @moduledoc """
  Scans working-tree files for forbidden source text in consumer tests.

  Plain strings match whole identifiers. Regular expressions retain their
  authored matching behavior.
  """

  @type token :: String.t() | Regex.t()
  @type violation :: {file :: String.t(), line :: pos_integer(), token()}

  @doc """
  Returns every forbidden token found in the configured files.

  The scan raises `ArgumentError` when its paths resolve to no files after the
  allowlist is applied.
  """
  @spec scan(keyword()) :: [violation()]
  def scan(options) when is_list(options) do
    paths = Keyword.fetch!(options, :dirs_or_globs)
    tokens = Keyword.fetch!(options, :tokens)
    allowlist = options |> Keyword.fetch!(:allowlist) |> allowlist_paths()

    files =
      paths
      |> Enum.flat_map(&resolve_path/1)
      |> Enum.uniq()
      |> Enum.reject(&(Path.expand(&1) in allowlist))
      |> Enum.sort()

    if files == [] do
      raise ArgumentError, "source scan resolved to zero files"
    end

    Enum.flat_map(files, &violations(&1, tokens))
  end

  defp resolve_path(path) do
    if File.dir?(path) do
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
    else
      path
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
    end
  end

  defp allowlist_paths(paths), do: MapSet.new(paths, &Path.expand/1)

  defp violations(file, tokens) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {source_line, line_number} ->
      for token <- tokens, matches?(source_line, token), do: {file, line_number, token}
    end)
  end

  defp matches?(source, %Regex{} = regex), do: Regex.match?(regex, source)

  defp matches?(source, token) when is_binary(token) do
    token
    |> Regex.escape()
    |> then(&Regex.compile!("(?<![[:alnum:]_])#{&1}(?![[:alnum:]_])"))
    |> Regex.match?(source)
  end
end
