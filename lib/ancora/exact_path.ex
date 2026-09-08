defmodule Ancora.ExactPath do
  @moduledoc false

  def valid?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and
      not String.contains?(path, ["*", "?", "[", "]", "{", "}", "\\", "\0"]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."]))
  end

  def valid?(_), do: false

  def check(path, _context) do
    if valid?(path),
      do: :ok,
      else: {:error, "expected an exact canonical project-relative file path"}
  end
end
