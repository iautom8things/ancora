defmodule Ancora.Schema.Verification do
  @moduledoc false

  # Leaf module: consumed at compile time by sibling schema definitions, so
  # it must not depend on any other project module (Zoi is external).

  @current_kind "tagged_tests"

  @retired_kinds ~w(
    command file source_file test_file guide_file readme_file
    workflow_file test doc workflow contract
  )

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.string(),
              target: Zoi.string() |> Zoi.default(""),
              covers: Zoi.list(Zoi.string()),
              execute: Zoi.boolean() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Verification"
  def schema, do: @schema

  def kinds, do: [@current_kind | @retired_kinds]
  def current_kind, do: @current_kind
  def retired_kinds, do: @retired_kinds

  def current_kind?(kind) when kind == @current_kind, do: true
  def current_kind?(_), do: false

  def retired_kind?(kind) when kind in @retired_kinds, do: true
  def retired_kind?(_), do: false

  def known_kind?(kind), do: current_kind?(kind) or retired_kind?(kind)
end
