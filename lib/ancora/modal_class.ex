defmodule Ancora.ModalClass do
  @moduledoc """
  Pure classifier for the normative strength of a requirement statement.

  Classifies a statement as one of `:must`, `:shall`, `:must_not`, `:shall_not`,
  `:should`, `:may`, or `:none`. The current append-only gate compares parsed
  priority fields directly and does not call this classifier.
  """

  @type modal ::
          :must | :shall | :must_not | :shall_not | :should | :may | :none

  @modals [:must, :shall, :must_not, :shall_not, :should, :may, :none]

  @modal_patterns [
    {:must_not, ~r/\b(?:must not|mustn t)\b/},
    {:shall_not, ~r/\b(?:shall not|shan t)\b/},
    {:must, ~r/\bmust\b/},
    {:shall, ~r/\bshall\b/},
    {:should, ~r/\bshould\b/},
    {:may, ~r/\bmay\b/}
  ]

  @doc """
  Classifies a statement string into a modal atom.

  Case and punctuation insensitive. Returns `:none` for any binary input
  that does not carry a recognized modal verb. Negative forms take
  precedence over positive forms.
  """
  @spec classify(binary()) :: modal()
  def classify(statement) when is_binary(statement) do
    normalized =
      statement
      |> String.downcase()
      |> strip_punctuation()

    Enum.find_value(@modal_patterns, :none, fn {modal, pattern} ->
      if Regex.match?(pattern, normalized), do: modal
    end)
  end

  @doc """
  Lists every modal atom in a stable order.
  """
  @spec modals() :: [modal()]
  def modals, do: @modals

  @doc """
  Returns `true` when moving from `prior` to `current` is a modal-class
  downgrade.

  Total over the 7 × 7 Cartesian product of modals. Behaviour:

  * Identity pairs return `false`.
  * Transitions starting from `:none` return `false` — there is no
    normative force to lose.
  * Transitions ending at `:none` return `true` — `:none` is strictly
    weaker than any recognized modal.
  * Within a polarity family (positive `{:must, :shall, :should, :may}`,
    negative `{:must_not, :shall_not}`), rank-decreasing transitions
    return `true`; rank-increasing transitions return `false`.
  * Positive → negative cross-polarity returns `true`.
  * Negative → positive cross-polarity returns `false` — polarity loss
    is a separate append-only concern, not a modal-class downgrade.
  """
  @spec downgrade?(modal(), modal()) :: boolean()
  def downgrade?(prior, current) when prior in @modals and current in @modals do
    cond do
      prior == current -> false
      prior == :none -> false
      current == :none -> true
      family(prior) == family(current) -> rank(current) < rank(prior)
      family(prior) == :positive and family(current) == :negative -> true
      true -> false
    end
  end

  defp family(m) when m in [:must, :shall, :should, :may], do: :positive
  defp family(m) when m in [:must_not, :shall_not], do: :negative
  defp family(:none), do: :none

  defp rank(:must), do: 6
  defp rank(:shall), do: 5
  defp rank(:must_not), do: 6
  defp rank(:shall_not), do: 5
  defp rank(:should), do: 3
  defp rank(:may), do: 2
  defp rank(:none), do: 0

  defp strip_punctuation(statement) do
    statement
    |> String.replace(~r/[[:punct:]]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
