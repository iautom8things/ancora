Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.IndexTest do
  use Ancora.TestCase

  alias Ancora.Index
  alias Ancora.Parser
  alias Ancora.Schema.Meta

  @fixtures Path.expand("../fixtures/specs", __DIR__)

  describe "build" do
    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "indexes authored specs and decisions and exposes Ancora.index/2", %{root: root} do
      write_spec(root, "alpha", """
      # Alpha

      ```spec-meta
      id: alpha.subject
      kind: module
      status: active
      ```

      ```spec-requirements
      - id: alpha.requirement
        statement: Alpha requirement
      ```
      """)

      write_decision(root, "policy", """
      ---
      id: alpha.decision.policy
      status: accepted
      date: 2026-08-21
      affects:
        - alpha.subject
      ---

      # Policy

      ## Context

      Why.

      ## Decision

      What.

      ## Consequences

      Effects.
      """)

      index = Ancora.index(root)

      assert index["spec_dir"] == ".spec"
      assert index["authored_dir"] == ".spec/specs"
      assert [%{"meta" => %Meta{id: "alpha.subject"}}] = index["subjects"]
      assert [%{"meta" => %{"id" => "alpha.decision.policy"}}] = index["decisions"]
      assert index["summary"]["subjects"] == 1
      assert index["summary"]["decisions"] == 1
      refute Map.has_key?(index, "test_tags")
      assert Index.build(root)["subjects"] |> length() == 1
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "garbage kind on an indexed corpus is spec/parse_error naming the file and entry",
         %{root: root} do
      write_spec(root, "garbage", """
      # Garbage

      ```spec-meta
      id: garbage.indexed
      kind: module
      status: active
      ```

      ```spec-verification
      - kind: bananas
        covers:
          - garbage.indexed
      ```
      """)

      index = Index.build(root)

      assert Enum.any?(index["findings"], fn finding ->
               finding.code == "spec/parse_error" and
                 finding.file =~ "garbage.spec.md" and
                 finding.message =~ "bananas"
             end)
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "unresolved affects is adr/affects_unresolved at error severity", %{root: root} do
      write_spec(root, "real", """
      # Real

      ```spec-meta
      id: real.subject
      kind: module
      status: active
      ```
      """)

      write_decision(root, "ghost", """
      ---
      id: real.decision.ghost
      status: accepted
      date: 2026-08-21
      affects:
        - ancora.ghost.requirement
      ---

      # Ghost

      ## Context

      Why.

      ## Decision

      What.

      ## Consequences

      Effects.
      """)

      index = Index.build(root)

      assert Enum.any?(index["findings"], fn finding ->
               finding.code == "adr/affects_unresolved" and
                 finding.severity == :error and
                 finding.message =~ "ancora.ghost.requirement"
             end)
    end
  end

  describe "consumer fixtures" do
    @tag spec: "ancora.parsing.consumer_corpora_parse"
    test "one fixture from each consumer parses with only format/retired_construct" do
      fixtures = [
        Path.join(@fixtures, "atlas/cli.spec.md"),
        Path.join(@fixtures, "engage/admin-recommendations.spec.md"),
        Path.join(@fixtures, "builder/builder.spec_infrastructure.spec.md"),
        Path.join(@fixtures, "argos/deploy-boot-migration.spec.md")
      ]

      assert length(fixtures) == 4

      for path <- fixtures do
        spec = Parser.parse_file(path, Path.dirname(path))
        codes = spec["findings"] |> Enum.map(& &1.code) |> Enum.uniq()

        assert codes -- ["format/retired_construct"] == [],
               "#{path} had unexpected findings: #{inspect(spec["findings"])}"

        assert "format/retired_construct" in codes,
               "#{path} expected format/retired_construct, got #{inspect(codes)}"

        assert spec["meta"]
      end
    end
  end
end
