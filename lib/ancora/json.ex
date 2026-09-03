defmodule Ancora.Json do
  @moduledoc "JSON encoding for gate reports."

  @spec encode!(term()) :: String.t()
  def encode!(value), do: Jason.encode!(value)
end
