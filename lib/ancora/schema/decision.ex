defmodule Ancora.Schema.Decision do
  @moduledoc false

  @statuses ~w(accepted deprecated superseded)

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Ancora.Schema.Id.id(),
              status: Zoi.enum(@statuses),
              date: Zoi.string(),
              affects: Zoi.list(Zoi.string()),
              retires: Zoi.list(Zoi.string()) |> Zoi.optional(),
              superseded_by: Ancora.Schema.Id.id() |> Zoi.optional(),
              change_type: Zoi.string() |> Zoi.optional(),
              reverses_what: Zoi.string() |> Zoi.optional(),
              replaces: Zoi.list(Ancora.Schema.Id.id()) |> Zoi.optional(),
              supersedes: Zoi.any() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
  def statuses, do: @statuses
end
