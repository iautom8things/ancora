defmodule Ancora.Derive.AckTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ancora.Derive.Ack

  @moduletag spec: "ancora.derive.acknowledgment_is_substantive"

  @words ~w(detector compares source clauses requirements scenarios bindings changes canonical)
  @whitespace ["  ", "\t", "\n      "]

  property "whitespace_never_acknowledges while a word edit does" do
    check all(
            words <- list_of(member_of(@words), min_length: 4, max_length: 7),
            position <- integer(0..(length(words) - 1)),
            replacement <- member_of(@words) |> filter(&(&1 != Enum.at(words, position))),
            requirement_whitespace <-
              list_of(member_of(@whitespace), length: length(words) + 1),
            scenario_whitespace <-
              list_of(member_of(@whitespace), length: length(words) + 1)
          ) do
      statement = Enum.join(words, " ")
      scenario = Enum.join(Enum.reverse(words), " ")
      changed_statement = words |> List.replace_at(position, replacement) |> Enum.join(" ")
      base = spec(statement, scenario)

      whitespace =
        spec(
          join_with_whitespace(words, requirement_whitespace),
          join_with_whitespace(Enum.reverse(words), scenario_whitespace)
        )

      changed = spec(changed_statement, scenario)

      refute base == whitespace
      refute Ack.acknowledged?(base, whitespace)
      assert Ack.acknowledged?(base, changed)
    end
  end

  test "nil source parses as an empty acknowledgment" do
    assert {:ok, %{requirements: [], scenarios: []}} = Ack.parse(nil)
    assert Ack.substantive?(nil, spec("The detector compares source clauses."))
  end

  test "broken YAML on either side is not substantive" do
    valid = spec("The detector compares source clauses.")
    broken = ack_block("- id: [unterminated")

    refute Ack.substantive?(broken, valid)
    refute Ack.substantive?(valid, broken)
  end

  test "non-list acknowledgment block is rejected" do
    assert {:error, {:invalid_ack_block, :requirements, %{"id" => "app.req"}}} =
             Ack.parse(ack_block("id: app.req"))
  end

  test "unparseable acknowledgment block is rejected" do
    assert {:error, {:invalid_ack_block, :requirements, _reason}} =
             Ack.parse(ack_block("- id: [unterminated"))
  end

  test "meta_edit_does_not_acknowledge" do
    base = spec("The detector shall compare source clauses.")
    head = String.replace(base, "summary: old", "summary: newly described")
    refute Ack.acknowledged?(base, head)
  end

  test "added, removed, and field-changed scenario entries acknowledge" do
    base = spec("The detector shall compare source clauses.")

    added =
      String.replace(
        base,
        "```yaml spec-scenarios\n",
        "```yaml spec-scenarios\n- id: app.scenario.added\n  given: [input]\n  when: [run]\n  then: [output]\n  covers: [app.req]\n"
      )

    assert Ack.acknowledged?(base, added)
    assert Ack.acknowledged?(added, base)
    assert Ack.acknowledged?(added, String.replace(added, "output", "changed output"))
  end

  defp spec(statement, scenario \\ "input stays stable") do
    """
    # Subject

    ```yaml spec-meta
    id: app.subject
    kind: module
    status: draft
    summary: old
    ```

    ```yaml spec-requirements
    - id: app.req
      statement: #{statement}
      priority: must
      stability: stable
    ```

    ```yaml spec-scenarios
    - id: app.scenario.one
      given:
        - "#{scenario}"
      when:
        - "#{scenario}"
      then:
        - "#{scenario}"
      covers:
        - app.req
    ```
    """
  end

  defp join_with_whitespace(words, whitespace) do
    [leading | rest] = whitespace
    {gaps, [trailing]} = Enum.split(rest, length(words) - 1)

    leading <>
      (words
       |> Enum.zip(gaps ++ [""])
       |> Enum.map_join(fn {word, gap} -> word <> gap end)) <>
      trailing
  end

  defp ack_block(yaml) do
    """
    ```yaml spec-requirements
    #{yaml}
    ```
    """
  end
end
