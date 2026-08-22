Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.DecisionParserTest do
  use Ancora.TestCase

  alias Ancora.DecisionParser
  alias Ancora.DecisionParser.Affects
  alias Ancora.Finding

  describe "parse_file/2" do
    @tag spec: "ancora.parsing.adr_grammar"
    test "extracts frontmatter, title, and required sections", %{root: root} do
      path =
        write_decision(root, "governance", """
        ---
        id: repo.governance.policy
        status: accepted
        date: 2026-03-11
        affects:
          - repo.governance
          - package.subject
        ---

        # Governance Policy

        ## Context

        Why the policy exists.

        ## Decision

        What the durable policy is.

        ## Consequences

        What changes because of it.
        """)

      decision = DecisionParser.parse_file(path, root)

      assert decision["file"] == ".spec/decisions/governance.md"
      assert decision["title"] == "Governance Policy"
      assert decision["meta"]["id"] == "repo.governance.policy"
      assert decision["meta"]["status"] == "accepted"
      assert decision["meta"]["affects"] == ["repo.governance", "package.subject"]
      assert decision["sections"] == ["Context", "Decision", "Consequences"]
      assert decision["parse_errors"] == []
      refute Enum.any?(decision["findings"], &(&1.code == "adr/missing_section"))
      refute Enum.any?(decision["findings"], &(&1.code == "adr/parse_error"))
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "change_type, supersedes, replaces, and reverses_what are silent", %{root: root} do
      path =
        write_decision(root, "clarifies", """
        ---
        id: example.decision.clarifies
        status: accepted
        date: 2026-08-21
        change_type: clarifies
        supersedes: example.decision.old
        replaces:
          - example.decision.old
        reverses_what: the old rule
        affects:
          - example.subject
        ---

        # Clarifies

        ## Context

        Why.

        ## Decision

        What.

        ## Consequences

        Effects.
        """)

      decision = DecisionParser.parse_file(path, root)

      assert decision["parse_errors"] == []
      assert decision["meta"]["change_type"] == "clarifies"
      assert decision["meta"]["replaces"] == ["example.decision.old"]

      refute Enum.any?(decision["findings"], fn finding ->
               String.contains?(finding.message, "change_type") or
                 String.contains?(finding.message, "supersedes") or
                 String.contains?(finding.message, "replaces") or
                 String.contains?(finding.message, "reverses_what")
             end)
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "missing Consequences fires adr/missing_section naming Consequences", %{root: root} do
      path =
        write_decision(root, "no_consequences", """
        ---
        id: example.decision.noconseq
        status: accepted
        date: 2026-08-21
        affects:
          - example.subject
        ---

        # No Consequences

        ## Context

        Why.

        ## Decision

        What.
        """)

      decision = DecisionParser.parse_file(path, root)

      assert Enum.any?(decision["findings"], fn %Finding{} = finding ->
               finding.code == "adr/missing_section" and
                 finding.message =~ "Consequences"
             end)
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "missing Context and missing Decision each fire adr/missing_section", %{root: root} do
      path =
        write_decision(root, "only_consequences", """
        ---
        id: example.decision.onlyc
        status: accepted
        date: 2026-08-21
        affects:
          - example.subject
        ---

        # Only Consequences

        ## Consequences

        Effects.
        """)

      decision = DecisionParser.parse_file(path, root)
      details = Enum.filter(decision["findings"], &(&1.code == "adr/missing_section"))

      assert Enum.any?(details, &(&1.message =~ "Context"))
      assert Enum.any?(details, &(&1.message =~ "Decision"))
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "missing frontmatter is adr/parse_error", %{root: root} do
      path =
        write_decision(root, "missing_frontmatter", """
        # Missing Frontmatter

        ## Context

        Missing metadata.
        """)

      decision = DecisionParser.parse_file(path, root)

      assert decision["meta"] == nil
      assert "decision frontmatter missing" in decision["parse_errors"]

      assert Enum.any?(decision["findings"], fn finding ->
               finding.code == "adr/parse_error" and finding.file =~ "missing_frontmatter.md"
             end)
    end

    @tag spec: "ancora.parsing.stable_public_api"
    test "parse_file/2 is exported and documented as stable" do
      assert {:module, _} = Code.ensure_loaded(DecisionParser)
      assert function_exported?(DecisionParser, :parse_file, 2)
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(DecisionParser)

      moduledoc =
        case module_doc do
          %{"en" => text} -> text
          :none -> ""
        end

      assert moduledoc =~ "semver-stable"
    end
  end

  describe "Affects" do
    @tag spec: "ancora.parsing.adr_grammar"
    test "empty affects emits adr/affects_empty" do
      decision = %{
        "file" => ".spec/decisions/empty.md",
        "meta" => %{
          "id" => "adr.empty",
          "status" => "accepted",
          "affects" => []
        }
      }

      index = %{"subjects" => [%{"meta" => %{"id" => "subj.x"}}], "decisions" => [decision]}
      codes = Affects.validate(decision, index) |> Enum.map(& &1.code)
      assert "adr/affects_empty" in codes
      refute "adr/affects_unresolved" in codes
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "unresolved affect emits adr/affects_unresolved naming the id" do
      decision = %{
        "file" => ".spec/decisions/ghost.md",
        "meta" => %{
          "id" => "adr.ghost",
          "status" => "accepted",
          "affects" => ["ancora.ghost.requirement"]
        }
      }

      index = %{"subjects" => [%{"meta" => %{"id" => "subj.x"}}], "decisions" => [decision]}
      [diagnostic] = Affects.validate(decision, index)
      assert diagnostic.code == "adr/affects_unresolved"
      assert diagnostic.detail == "ancora.ghost.requirement"
    end

    @tag spec: "ancora.parsing.adr_grammar"
    test "resolved subject, requirement, scenario, or decision ids are silent" do
      decision = %{
        "file" => ".spec/decisions/ok.md",
        "meta" => %{
          "id" => "adr.ok",
          "status" => "accepted",
          "affects" => ["subj.x", "subj.x.req", "subj.x.scene"]
        }
      }

      index = %{
        "subjects" => [
          %{
            "meta" => %{"id" => "subj.x"},
            "requirements" => [%{"id" => "subj.x.req"}],
            "scenarios" => [%{"id" => "subj.x.scene"}]
          }
        ],
        "decisions" => [decision]
      }

      assert Affects.validate(decision, index) == []
    end
  end
end
