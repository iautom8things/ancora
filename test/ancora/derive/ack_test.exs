defmodule Ancora.Derive.AckTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ancora.Derive.Ack

  @moduletag spec: "ancora.derive.acknowledgment_is_substantive"

  property "whitespace_never_acknowledges while a word edit does" do
    check all(gap <- member_of([" ", "  ", "\n      ", "\t"])) do
      base = spec("The detector shall compare source clauses.")
      whitespace = spec("The#{gap}detector#{gap}shall#{gap}compare#{gap}source#{gap}clauses.")
      changed = spec("The detector shall compare canonical clauses.")

      refute Ack.acknowledged?(base, whitespace)
      assert Ack.acknowledged?(base, changed)
    end
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
        "```yaml spec-scenarios\n[]",
        "```yaml spec-scenarios\n- id: app.scenario.one\n  given: [input]\n  when: [run]\n  then: [output]\n  covers: [app.req]"
      )

    assert Ack.acknowledged?(base, added)
    assert Ack.acknowledged?(added, base)
    assert Ack.acknowledged?(added, String.replace(added, "output", "changed output"))
  end

  defp spec(statement) do
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
    []
    ```
    """
  end
end
