Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.OverlapTest do
  use Ancora.TestCase

  alias Ancora.Index
  alias Ancora.Overlap

  describe "duplicate_covers" do
    @tag spec: "ancora.parsing.overlap_checks"
    test "two verification entries in different subjects with identical covers lists fire", %{
      root: root
    } do
      write_spec(root, "alpha", spec_with_covers("alpha", ["shared.one", "shared.two"]))
      write_spec(root, "beta", spec_with_covers("beta", ["shared.one", "shared.two"]))

      index = Index.build(root)
      findings = Overlap.analyze(index["subjects"])

      dup = Enum.filter(findings, &(&1.code == "overlap/duplicate_covers"))

      assert dup != [],
             "Would fail if Overlap.analyze compared scenarios instead of verification covers lists, or scoped duplicates to one subject"

      assert Enum.any?(dup, fn finding ->
               finding.message =~ "alpha" and finding.message =~ "beta"
             end)
    end

    @tag spec: "ancora.parsing.overlap_checks"
    test "disjoint covers lists do not collide", %{root: root} do
      write_spec(root, "alpha", spec_with_covers("alpha", ["alpha.requirement"]))
      write_spec(root, "beta", spec_with_covers("beta", ["beta.requirement"]))

      index = Index.build(root)

      refute Enum.any?(
               Overlap.analyze(index["subjects"]),
               &(&1.code == "overlap/duplicate_covers")
             )
    end
  end

  describe "must_stem_collision" do
    @tag spec: "ancora.parsing.overlap_checks"
    test "two must requirements in one subject sharing a normalized stem fire", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: alpha.first
        statement: The system MUST reject invalid input.
        priority: must
      - id: alpha.second
        statement: The SYSTEM must reject invalid input
        priority: must
      ```
      """)

      index = Index.build(root)
      findings = Overlap.analyze(index["subjects"])

      assert Enum.any?(findings, &(&1.code == "overlap/must_stem_collision")),
             "Would fail if must-stem normalization skipped punctuation or case folding"
    end

    @tag spec: "ancora.parsing.overlap_checks"
    test "cross-subject must stems and non-must priorities do not collide", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```yaml spec-meta
      id: alpha
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: alpha.first
        statement: The system MUST reject invalid input.
        priority: must
      - id: alpha.should
        statement: The system MUST reject invalid input.
        priority: should
      ```
      """)

      write_spec(root, "beta", """
      # Beta

      ```yaml spec-meta
      id: beta
      kind: module
      status: active
      ```

      ```yaml spec-requirements
      - id: beta.first
        statement: The system MUST reject invalid input.
        priority: must
      ```
      """)

      index = Index.build(root)

      refute Enum.any?(
               Overlap.analyze(index["subjects"]),
               &(&1.code == "overlap/must_stem_collision")
             )
    end
  end

  describe "purity" do
    @tag spec: "ancora.parsing.overlap_checks"
    test "identical subjects return equal findings and do not consult prior state", %{root: root} do
      write_spec(root, "alpha", spec_with_covers("alpha", ["alpha.requirement"]))
      index = Index.build(root)
      first = Overlap.analyze(index["subjects"])
      second = Overlap.analyze(index["subjects"])
      assert first == second
    end
  end

  defp spec_with_covers(id, covers) do
    covers_yaml = Enum.map_join(covers, "\n", &("        - " <> &1))

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

    ```yaml spec-verification
    - kind: tagged_tests
      covers:
    #{covers_yaml}
    ```
    """
  end
end
