defmodule Ancora.Schema.Requirement do
  @moduledoc false

  @polarities ~w(positive negative)

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Ancora.Schema.Id.id(),
              statement: Zoi.string(),
              priority: Zoi.string() |> Zoi.optional(),
              stability: Zoi.string() |> Zoi.optional(),
              realized_by: Zoi.any() |> Zoi.optional(),
              polarity: Zoi.enum(@polarities) |> Zoi.optional(),
              refines: Ancora.Schema.Id.id() |> Zoi.optional(),
              supersedes: Ancora.Schema.Id.id() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Requirement"
  def schema, do: @schema

  def polarities, do: @polarities
end
