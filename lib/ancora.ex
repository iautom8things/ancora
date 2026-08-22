defmodule Ancora do
  @moduledoc """
  Spec-anchored traceability and drift detection for Elixir.
  """

  alias Ancora.Index

  @doc """
  Builds the in-memory corpus index for `root`.

  Delegates to `Ancora.Index.build/2`. The semver-stable parse API is
  `Ancora.Parser.parse_file/2` and `Ancora.DecisionParser.parse_file/2`.
  """
  @spec index(String.t(), keyword()) :: map()
  def index(root \\ File.cwd!(), opts \\ []) when is_binary(root) and is_list(opts) do
    Index.build(root, opts)
  end
end
