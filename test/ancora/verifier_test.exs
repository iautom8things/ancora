Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.VerifierTest do
  use Ancora.TestCase

  alias Ancora.Index
  alias Ancora.Verifier

  describe "unknown_reference" do
    @tag spec: "ancora.parsing.structural_references"
    test "scenario covers naming a missing id is spec/unknown_reference", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: alpha.requirement
        statement: Alpha shall hold.
        priority: must
      ```

      ```yaml spec-scenarios
      - id: alpha.scenario.unknown
        covers:
          - ancora.nope.missing
        given:
          - a precondition
        when:
          - an action
        then:
          - an outcome
      ```
      """)

      findings = Verifier.verify(Index.build(root))

      assert Enum.any?(findings, fn finding ->
               finding.code == "spec/unknown_reference" and
                 finding.message =~ "alpha.scenario.unknown" and
                 finding.message =~ "ancora.nope.missing"
             end),
             "Would fail if Verifier skipped scenario covers: when checking spec/unknown_reference"
    end

    @tag spec: "ancora.parsing.structural_references"
    test "verification covers and spec-meta decisions also emit spec/unknown_reference", %{
      root: root
    } do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      decisions:
        - alpha.decision.ghost
      ```

      ```yaml spec-requirements
      - id: alpha.requirement
        statement: Alpha shall hold.
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - alpha.missing.cover
      ```
      """)

      findings = Verifier.verify(Index.build(root))
      unknown = Enum.filter(findings, &(&1.code == "spec/unknown_reference"))

      assert Enum.any?(unknown, &(&1.message =~ "alpha.decision.ghost"))
      assert Enum.any?(unknown, &(&1.message =~ "alpha.missing.cover"))
    end
  end

  describe "duplicate_id" do
    @tag spec: "ancora.parsing.structural_references"
    test "the same requirement id in two spec files fires once naming both files", %{root: root} do
      write_spec(root, "one", spec_with_requirement("one", "ancora.x.same"))
      write_spec(root, "two", spec_with_requirement("two", "ancora.x.same"))

      findings = Verifier.verify(Index.build(root))
      dups = Enum.filter(findings, &(&1.code == "spec/duplicate_id"))

      assert length(dups) == 1,
             "Would fail if Verifier emitted one duplicate_id per file instead of once naming both"

      [finding] = dups
      assert finding.message =~ "ancora.x.same"
      assert finding.message =~ "one.spec.md"
      assert finding.message =~ "two.spec.md"
    end
  end

  describe "invalid_id and missing_field" do
    @tag spec: "ancora.parsing.structural_references"
    test "a covers entry that is not a dotted identifier is spec/invalid_id", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-scenarios
      - id: alpha.scenario.bad
        covers:
          - Not A Valid Id
        given:
          - a precondition
        when:
          - an action
        then:
          - an outcome
      ```
      """)

      findings = Verifier.verify(Index.build(root))

      assert Enum.any?(findings, fn finding ->
               finding.code == "spec/invalid_id" and finding.message =~ "Not A Valid Id"
             end)
    end

    @tag spec: "ancora.parsing.structural_references"
    test "a scenario with empty given is spec/missing_field", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-scenarios
      - id: alpha.scenario.empty
        covers:
          - alpha.requirement
        given: []
        when:
          - an action
        then:
          - an outcome
      ```
      """)

      findings = Verifier.verify(Index.build(root))

      assert Enum.any?(findings, fn finding ->
               finding.code == "spec/missing_field" and finding.message =~ "given"
             end)
    end
  end

  describe "requirement_unverified" do
    @tag spec: "ancora.parsing.requirement_unverified"
    test "a requirement with no tagged_tests cover is spec/requirement_unverified at info", %{
      root: root
    } do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: alpha.requirement
        statement: Alpha shall hold.
        priority: must
      ```
      """)

      findings = Verifier.verify(Index.build(root))

      unverified =
        Enum.filter(findings, &(&1.code == "spec/requirement_unverified"))

      assert unverified != [],
             "Would fail if Verifier treated a missing tagged_tests covers: entry as verified"

      assert Enum.all?(unverified, &(&1.severity == :info))
      assert Enum.any?(unverified, &(&1.message =~ "alpha.requirement"))
    end

    @tag spec: "ancora.parsing.requirement_unverified"
    test "a tagged_tests cover silences requirement_unverified", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: alpha.requirement
        statement: Alpha shall hold.
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - alpha.requirement
      ```
      """)

      findings = Verifier.verify(Index.build(root))
      refute Enum.any?(findings, &(&1.code == "spec/requirement_unverified"))
    end
  end

  defp spec_with_requirement(subject, req_id) do
    """
    # #{subject}

    ```yaml spec-meta
    id: #{subject}
    kind: module
    status: active
    ```

    ```yaml spec-requirements
    - id: #{req_id}
      statement: Shared requirement.
      priority: must
    ```
    """
  end
end
