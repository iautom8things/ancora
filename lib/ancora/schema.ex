defmodule Ancora.Schema do
  @moduledoc false

  alias Ancora.Schema.{
    Decision,
    Exception,
    Meta,
    Requirement,
    Scenario,
    Verification
  }

  def meta, do: Meta.schema()
  def requirement, do: Requirement.schema()
  def scenario, do: Scenario.schema()
  def verification, do: Verification.schema()
  def exception, do: Exception.schema()
  def decision, do: Decision.schema()

  @doc """
  Validates a parsed block against its schema.

  Returns `{:ok, items}` or `{:error, message}`. `realized_by` is accepted
  as an untyped optional field (no tier schema). Retired verification
  kinds are accepted; a kind that is neither `tagged_tests` nor a known
  retired kind is a validation error.
  """
  def validate_block("spec-meta", data) do
    zoi_parse(meta(), data, "spec-meta")
  end

  def validate_block(tag, items) when is_list(items) do
    schema =
      case tag do
        "spec-requirements" -> requirement()
        "spec-scenarios" -> scenario()
        "spec-verification" -> verification()
        "spec-exceptions" -> exception()
      end

    items
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {item, idx}, {valid, errs} ->
      case parse_item(schema, tag, item, idx) do
        {:ok, parsed} -> {[parsed | valid], errs}
        {:error, message} -> {valid, [message | errs]}
      end
    end)
    |> case do
      {valid, []} -> {:ok, Enum.reverse(valid)}
      {_valid, errs} -> {:error, errs |> Enum.reverse() |> Enum.join("; ")}
    end
  end

  defp parse_item(schema, tag, item, idx) do
    with {:ok, parsed} <- Zoi.parse(schema, item),
         :ok <- maybe_reject_garbage_kind(tag, parsed, idx) do
      {:ok, parsed}
    else
      {:error, errors} when is_list(errors) ->
        {:error, format_item_errors(tag, idx, errors)}

      {:error, message} when is_binary(message) ->
        {:error, message}
    end
  end

  defp maybe_reject_garbage_kind("spec-verification", parsed, idx) do
    kind = parsed.kind

    if Verification.known_kind?(kind) do
      :ok
    else
      {:error, "spec-verification[#{idx}] unknown verification kind #{inspect(kind)}"}
    end
  end

  defp maybe_reject_garbage_kind(_tag, _parsed, _idx), do: :ok

  defp zoi_parse(schema, data, tag) do
    case Zoi.parse(schema, data) do
      {:ok, result} -> {:ok, result}
      {:error, errors} -> {:error, format_errors(tag, errors)}
    end
  end

  defp format_errors(tag, errors) do
    msgs = Enum.map(errors, & &1.message)
    "#{tag} validation failed: #{Enum.join(msgs, ", ")}"
  end

  defp format_item_errors(tag, idx, errors) do
    msgs = Enum.map(errors, & &1.message)
    "#{tag}[#{idx}] validation failed: #{Enum.join(msgs, ", ")}"
  end
end
