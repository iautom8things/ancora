Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.TagFindingsTest do
  use Ancora.TestCase

  alias Ancora.Finding
  alias Ancora.Index
  alias Ancora.TagFindings
  alias Ancora.TagScanner

  describe "findings/4" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "parse error on an unparseable test file is tags/parse_error", %{root: root} do
      write_spec(root, "alpha", spec_body("alpha"))
      write_test_file(root, "test/broken_test.exs", "defmodule do do\n")

      index = Index.build(root)
      {:ok, tag_map, parse_errors, dynamics} = TagScanner.scan([Path.join(root, "test")])
      findings = TagFindings.findings(index, tag_map, parse_errors, dynamics)

      assert Enum.any?(findings, &(&1.code == "tags/parse_error")),
             "Would fail if TagFindings dropped scanner parse errors instead of emitting tags/parse_error"
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "dynamic tag values emit tags/dynamic_value and do not satisfy the requirement", %{
      root: root
    } do
      write_spec(root, "alpha", spec_body("alpha"))

      write_test_file(root, "test/dynamic_test.exs", """
      defmodule DynamicTest do
        use ExUnit.Case

        @subject "alpha"

        @tag spec: @subject <> ".requirement"
        test "dynamic" do
          assert true
        end
      end
      """)

      index = Index.build(root)
      {:ok, tag_map, parse_errors, dynamics} = TagScanner.scan([Path.join(root, "test")])
      findings = TagFindings.findings(index, tag_map, parse_errors, dynamics)

      assert Enum.any?(findings, &(&1.code == "tags/dynamic_value"))

      assert Enum.any?(findings, fn finding ->
               finding.code == "tags/requirement_untagged" and
                 finding.message =~ "alpha.requirement"
             end),
             "Would fail if a guessed dynamic tag counted as coverage for the requirement"
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "a tag naming an id absent from the corpus is tags/unknown_requirement", %{root: root} do
      write_spec(root, "alpha", spec_body("alpha"))

      write_test_file(root, "test/ghost_test.exs", """
      defmodule GhostTest do
        use ExUnit.Case

        @tag spec: "alpha.ghost"
        test "ghost" do
          assert true
        end
      end
      """)

      index = Index.build(root)
      {:ok, tag_map, parse_errors, dynamics} = TagScanner.scan([Path.join(root, "test")])
      findings = TagFindings.findings(index, tag_map, parse_errors, dynamics)

      assert Enum.any?(findings, fn finding ->
               finding.code == "tags/unknown_requirement" and finding.message =~ "alpha.ghost"
             end)
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "a requirement with no tag anywhere is tags/requirement_untagged at info", %{root: root} do
      write_spec(root, "alpha", spec_body("alpha"))
      index = Index.build(root)
      findings = TagFindings.findings(index, %{}, [], [])

      untagged = Enum.filter(findings, &(&1.code == "tags/requirement_untagged"))
      assert untagged != []
      assert Enum.all?(untagged, &(&1.severity == :info))
      assert %Finding{code: "tags/requirement_untagged"} = hd(untagged)
    end
  end

  defp spec_body(id) do
    """
    # #{id}

    ```yaml spec-meta
    id: #{id}
    kind: module
    status: active
    ```

    ```yaml spec-requirements
    - id: #{id}.requirement
      statement: #{id} shall hold.
      priority: must
    ```

    ```yaml spec-scenarios
    - id: #{id}.scenario.one
      covers:
        - #{id}.requirement
      given:
        - a precondition
      when:
        - an action
      then:
        - an outcome
    ```

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
        - #{id}.requirement
    ```
    """
  end
end
