Code.require_file("case.exs", __DIR__)

defmodule AncoraReplay.Selection do
  @moduledoc false

  alias AncoraReplay.Case

  @spec load!(Path.t()) :: [Case.t()]
  def load!(path) do
    [header | rows] = path |> File.read!() |> String.split("\n", trim: true)

    unless header == "name\trepo\tsha\tkind\tfunctions" do
      raise "unexpected selection header in #{path}"
    end

    Enum.map(rows, &parse_row!/1)
  end

  defp parse_row!(row) do
    case String.split(row, "\t") do
      [name, repo, sha, kind, functions] ->
        %Case{
          name: name,
          repo: repo,
          sha: sha,
          kind: parse_kind!(kind),
          functions: String.split(functions, ",", trim: true)
        }

      _other ->
        raise "invalid selection row: #{inspect(row)}"
    end
  end

  defp parse_kind!("drift"), do: :drift
  defp parse_kind!("control"), do: :control
  defp parse_kind!(kind), do: raise("invalid replay kind: #{kind}")
end
