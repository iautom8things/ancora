defmodule Ancora.Schema.Meta do
  @moduledoc false

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Ancora.Schema.Id.id(),
              kind: Zoi.string(),
              status: Zoi.string(),
              summary: Zoi.string() |> Zoi.optional(),
              surface: Zoi.list(Zoi.string()) |> Zoi.optional(),
              decisions: Zoi.list(Ancora.Schema.Id.id()) |> Zoi.optional(),
              verification_minimum_strength: Zoi.string() |> Zoi.optional(),
              realized_by: Zoi.any() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Meta"
  def schema, do: @schema
end
