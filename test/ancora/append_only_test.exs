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

      assert Enum.any?(deleted, fn finding ->
               finding.message ==
                 "alpha.requirement deleted; no authorizing ADR names it — " <>
                   "add an accepted ADR whose affects: or retires: names the requirement id"
             end)
    end

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.append_authorization_is_requirement_scoped"
         ]
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

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.append_authorization_is_requirement_scoped"
         ]
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

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.append_authorization_is_requirement_scoped"
         ]
    test "ADR affecting one requirement does not authorize deleting its sibling", %{root: root} do
      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must"))
      write_adr(root, "drop", "accepted", ["alpha.one"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, &(&1.code == "append/requirement_deleted")),
             "Would fail if an ADR naming one requirement authorized deleting a different requirement in the same subject"
    end

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.retirement_vocabulary"
         ]
    test "accepted ADR retiring a subject authorizes deleting all of its requirements", %{
      root: root
    } do
      init_git_repo(root)

      write_files(root, %{
        "mix.exs" => """
        defmodule Fixture.MixProject do
          use Mix.Project
          def project, do: [app: :fixture]
        end
        """
      })

      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "must"))
      prior = Index.build(root)
      commit_all(root, "base subject")

      File.rm!(Path.join([root, ".spec", "specs", "alpha.spec.md"]))
      write_adr(root, "retire", "accepted", ["alpha"], ["alpha"])
      current = Index.build(root)

      refute Enum.any?(current["findings"], &(&1.code == "adr/affects_unresolved")),
             "Would fail if a retired subject still had to resolve in the current index"

      refute Enum.any?(AppendOnly.analyze(prior, current), fn finding ->
               finding.code == "append/requirement_deleted"
             end),
             "Would fail if a retired subject did not authorize deleting every requirement that belonged to it"

      assert %{stdout: validate_stdout, status: 0} =
               run_mix_subprocess(["spec.validate", "--root", root])

      refute validate_stdout =~ "adr/affects_unresolved"
      assert List.last(output_lines(validate_stdout)) == "spec.validate result=pass"

      assert %{stdout: check_stdout, status: 0} =
               run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])

      refute check_stdout =~ "adr/affects_unresolved"
      refute check_stdout =~ "append/requirement_deleted"
      assert List.last(output_lines(check_stdout)) == "spec.check result=pass"
    end

    @tag spec: "ancora.parsing.retirement_vocabulary"
    test "accepted ADR retiring an exact requirement authorizes its deletion", %{root: root} do
      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must"))
      write_adr(root, "retire", "accepted", ["alpha.one"], ["alpha.two"])
      current = Index.build(root)

      refute Enum.any?(AppendOnly.analyze(prior, current), fn finding ->
               finding.code == "append/requirement_deleted"
             end),
             "Would fail if retires could not authorize the exact requirement id it names"
    end

    @tag spec: "ancora.parsing.retirement_vocabulary"
    test "retiring one requirement does not authorize deleting its sibling", %{root: root} do
      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must"))
      write_adr(root, "retire", "accepted", ["alpha.one"], ["alpha.one"])
      current = Index.build(root)

      assert Enum.any?(AppendOnly.analyze(prior, current), fn finding ->
               finding.code == "append/requirement_deleted" and
                 finding.message =~ "alpha.two deleted"
             end),
             "Would fail if retiring one requirement authorized deleting another requirement in the same subject"
    end

    @tag spec: "ancora.parsing.retirement_vocabulary"
    test "retirement authorization is exact and bounded to the named subject", %{root: root} do
      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must"))
      write_spec(root, "alphabet", spec_with_reqs("alphabet", one: "must"))
      prior = Index.build(root)

      File.rm!(Path.join([root, ".spec", "specs", "alpha.spec.md"]))
      write_spec(root, "alphabet", spec_without_req("alphabet"))
      write_adr(root, "retire", "accepted", ["alpha"], ["alpha"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, fn finding ->
               finding.code == "append/requirement_deleted" and
                 finding.message =~ "alphabet.one deleted"
             end),
             "Would fail if retirement used prefix matching and authorized a deletion in another subject"

      refute Enum.any?(findings, &(&1.message =~ "alpha.one deleted")),
             "Would fail if retiring a subject did not authorize its own requirements"
    end

    @tag spec: "ancora.parsing.retirement_vocabulary"
    test "a non-accepted ADR cannot authorize deletion through retires", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_without_req("alpha"))
      write_adr(root, "retire", "deprecated", ["alpha.requirement"], ["alpha.requirement"])
      current = Index.build(root)

      assert Enum.any?(AppendOnly.analyze(prior, current), fn finding ->
               finding.code == "append/requirement_deleted"
             end),
             "Would fail if retires on a non-accepted ADR authorized a deletion"
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

      assert Enum.any?(downgraded, fn finding ->
               finding.message ==
                 "alpha.requirement: must → should; no authorizing ADR names it — " <>
                   "add an accepted ADR whose affects: names the requirement id"
             end)
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

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.append_authorization_is_requirement_scoped"
         ]
    test "ADR affecting one requirement does not authorize downgrading its sibling", %{root: root} do
      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_reqs("alpha", one: "must", two: "should"))
      write_adr(root, "weaken", "accepted", ["alpha.one"])
      current = Index.build(root)

      findings = AppendOnly.analyze(prior, current)

      assert Enum.any?(findings, &(&1.code == "append/must_downgraded")),
             "Would fail if an ADR naming one requirement authorized downgrading a different requirement in the same subject"
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

    @tag spec: [
           "ancora.gate.two_append_guards",
           "ancora.parsing.retirement_vocabulary"
         ]
    test "retires does not authorize a must downgrade", %{root: root} do
      write_spec(root, "alpha", spec_with_req("alpha", "must"))
      prior = Index.build(root)

      write_spec(root, "alpha", spec_with_req("alpha", "should"))
      write_adr(root, "retire", "accepted", ["alpha"], ["alpha"])
      current = Index.build(root)

      assert Enum.any?(AppendOnly.analyze(prior, current), fn finding ->
               finding.code == "append/must_downgraded"
             end),
             "Would fail if retiring a subject authorized weakening a requirement that remains in the corpus"
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

  defp spec_with_reqs(id, requirements) do
    requirements_yaml =
      Enum.map_join(requirements, "\n", fn {name, priority} ->
        """
        - id: #{id}.#{name}
          statement: #{id}.#{name} shall hold.
          priority: #{priority}
        """
        |> String.trim()
      end)

    """
    # #{id}

    ```yaml spec-meta
    id: #{id}
    kind: module
    status: active
    ```

    ```yaml spec-requirements
    #{requirements_yaml}
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
    write_adr(root, name, status, affects, [])
  end

  defp write_adr(root, name, status, affects, retires) do
    affects_yaml = Enum.map_join(affects, "\n", &("  - " <> &1))

    retires_yaml =
      case retires do
        [] -> ""
        ids -> "retires:\n" <> Enum.map_join(ids, "\n", &("  - " <> &1)) <> "\n"
      end

    write_decision(root, name, """
    ---
    id: alpha.decision.#{name}
    status: #{status}
    date: 2026-08-21
    affects:
    #{affects_yaml}
    #{retires_yaml}---

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
