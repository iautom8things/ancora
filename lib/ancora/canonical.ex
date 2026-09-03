defmodule Ancora.Canonical do
  @moduledoc """
  Canonical form used by the source drift detector.

  Normalization strips quoted-AST metadata and makes no other changes. In
  particular, variable names, charlists, and sigils remain distinct. Plain
  `mix format` preserves those literal forms. A `mix format --migrate` rewrite
  can change them and should be acknowledged in the subject spec.
  """

  @doc "Strips metadata from every quoted-AST node."
  @spec normalize(Macro.t()) :: Macro.t()
  def normalize(ast) do
    Macro.prewalk(ast, fn
      {form, metadata, arguments} when is_list(metadata) -> {form, [], arguments}
      node -> node
    end)
  end
end
