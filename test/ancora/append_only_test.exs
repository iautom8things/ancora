Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.AppendOnlyTest do
  use Ancora.TestCase

  alias Ancora.AppendOnly
  alias Ancora.Index

  describe "requirement_deleted" do
    @tag spec: "ancora.gate.two_append_guards"
    test "deleted requirement without an authorizing ADR is append/requirement_deleted at error",
         %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_without_req("alpha"))
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)
      deleted = Enum.filter(findings, &(&1.code == "append/requirement_deleted"))

      assert deleted != [],
             "Would fail if AppendOnly omitted append/requirement_deleted when a base requirement is absent on HEAD with no accepted ADR"

      assert Enum.all?(deleted, &(&1.severity == :error))
      assert Enum.any?(deleted, &(&1.message =~ "alpha.requirement"))
    end

    @tag spec: "ancora.parsing.append_authorization_is_requirement_scoped"
    test "accepted ADR whose affects names the requirement suppresses deletion", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_without_req("alpha"))
      write_adr(root, "drop", "accepted", ["alpha.requirement"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      refute Enum.any?(findings, &(&1.code == "append/requirement_deleted")),
             "Would fail if an accepted ADR could not authorize the exact requirement id it names"
    end

    @tag spec: "ancora.parsing.append_authorization_is_requirement_scoped"
    test "accepted ADR whose affects names only the subject does not authorize deletion", %{
      root: root
    } do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_without_req("alpha"))
      write_adr(root, "drop", "accepted", ["alpha"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, &(&1.code == "append/requirement_deleted")),
             "Would fail if a subject-scoped ADR still granted blanket authorization to delete any requirement in that subject"
    end

    @tag spec: "ancora.gate.two_append_guards"
    test "a non-accepted ADR does not authorize deletion", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_without_req("alpha"))
      write_adr(root, "drop", "deprecated", ["alpha.requirement"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, &(&1.code == "append/requirement_deleted")),
             "Would fail if AppendOnly treated a non-accepted ADR as authorization"
    end
  end

  describe "must_downgraded" do
    @tag spec: "ancora.gate.two_append_guards"
    test "must to should without an ADR is append/must_downgraded at error", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)
      downgraded = Enum.filter(findings, &(&1.code == "append/must_downgraded"))

      assert downgraded != [],
             "Would fail if AppendOnly omitted append/must_downgraded when priority moves from must to should with no accepted ADR"

      assert Enum.all?(downgraded, &(&1.severity == :error))
    end

    @tag spec: "ancora.parsing.append_authorization_is_requirement_scoped"
    test "accepted ADR whose affects names only the subject does not authorize must downgrade", %{
      root: root
    } do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      write_adr(root, "weaken", "accepted", ["alpha"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, &(&1.code == "append/must_downgraded")),
             "Would fail if a subject-scoped ADR still granted blanket authorization to downgrade any must in that subject"
    end

    @tag spec: "ancora.parsing.append_authorization_is_requirement_scoped"
    test "accepted ADR whose affects names the requirement suppresses must_downgraded", %{
      root: root
    } do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      write_adr(root, "weaken", "accepted", ["alpha.requirement"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      refute Enum.any?(findings, &(&1.code == "append/must_downgraded")),
             "Would fail if an accepted ADR could not authorize the exact requirement id it names"
    end

    @tag spec: "ancora.gate.two_append_guards"
    test "a non-accepted ADR does not authorize a must to should downgrade", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      write_adr(root, "weaken", "superseded", ["alpha"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)
      assert Enum.any?(findings, &(&1.code == "append/must_downgraded"))
    end

    @tag spec: "ancora.gate.two_append_guards"
    test "should to must and same-priority rewrites are not guarded", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      current = Index.build(root)

      refute Enum.any?(AppendOnly.analyze(prior, current), &(&1.code == "append/must_downgraded"))
    end
  end

  defp spec_with_req(id, priority) do
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
      priority: #{priority}
    ```
    """
  end

  defp spec_without_req(id) do
    """
    # #{id}

    ```yaml spec-meta
    id: #{id}
    kind: module
    status: active
    ```
    """
  end

  defp write_adr(root, name, status, affects) do
    affects_yaml = Enum.map_join(affects, "\n", &("  - " <> &1))

    write_decision(root, name, """
    ---
    id: alpha.decision.#{name}
    status: #{status}
    date: 2026-08-21
    affects:
    #{affects_yaml}
    ---

    # #{name}

    ## Context

    Why.

    ## Decision

    What.

    ## Consequences

    Effects.
    """)
  end
end
