Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.IndexTest do
  use Ancora.TestCase

  alias Ancora.Index
  alias Ancora.Parser
  alias Ancora.Schema.Meta

  @fixtures Path.expand("../fixtures/specs", __DIR__)

  describe "build" do
    @tag spec: "ancora.gate.preflight_hard_fails"
    test "returns the requested workspace lookup failure as data", %{root: root} do
      assert {:error, message} = Index.build(root, spec_dir: ".spec/specs")
      assert message =~ "--spec-dir selects the ancora workspace directory"
      assert message =~ ".spec/specs/specs directory not found"
    end

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

    @tag spec: "ancora.parsing.structural_references"
    @tag spec: "ancora.parsing.stable_public_api"
    test "schema-rejected metadata reports the exact error and every reader handles it", %{
      root: root
    } do
      init_git_repo(root)

      write_files(root, %{
        "mix.exs" => """
        defmodule Fixture.MixProject do
          use Mix.Project
          def project, do: [app: :fixture, version: "0.1.0"]
        end
        """,
        "lib/sample.ex" => "defmodule Sample do\nend\n"
      })

      fixtures = [
        {"missing status",
         """
         id: broken.subject
         kind: module
         """, "status"},
        {"malformed id",
         """
         id: Bad Subject!
         kind: module
         status: active
         """, "id"}
      ]

      for {name, meta, rejected_field} <- fixtures do
        write_spec(root, "broken", """
        # Broken

        ```yaml spec-meta
        #{meta}```
        """)

        commit_all(root, name)

        spec = root |> Path.join(".spec/specs/broken.spec.md") |> Parser.parse_file(root)

        assert spec["meta"] == :rejected
        assert Enum.map(spec["findings"], & &1.code) == ["spec/parse_error"]
        assert hd(spec["findings"]).subject == nil
        assert hd(spec["findings"]).message =~ "field: #{rejected_field}"

        assert Map.keys(spec) |> Enum.sort() ==
                 ~w(exceptions file findings meta parse_errors requirements scenarios title verification)

        check = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
        assert check.status == 1
        assert spec_finding_codes(check.stdout) == ["spec/parse_error"]
        assert_rejected_meta_line(check.stdout, rejected_field)
        assert List.last(output_lines(check.stdout)) =~ "spec.check result=fail tier=branch"

        validate = run_mix_subprocess(["spec.validate", "--root", root])
        assert validate.status == 1
        assert spec_finding_codes(validate.stdout) == ["spec/parse_error"]
        assert_rejected_meta_line(validate.stdout, rejected_field)

        assert List.last(output_lines(validate.stdout)) =~
                 "spec.validate result=fail tier=validate"

        for {args, opts, heading} <- [
              {["spec.status", "--root", root], [], "Spec Led Status"},
              {[
                 "run",
                 "-e",
                 "File.cd!(#{inspect(root)}, fn -> Mix.Tasks.Spec.Next.run([\"--base\", \"HEAD\"]) end)"
               ], [], "Spec Led Next"},
              {["spec.prime", "--root", root, "--base", "HEAD"], [], "Spec Led Prime"}
            ] do
          result = run_mix_subprocess(args, opts)
          assert result.status == 0, result.stdout <> result.stderr
          assert result.stdout =~ heading
          refute result.stderr =~ "** ("
        end

        review = run_mix_subprocess(["spec.review", "--root", root, "--base", "HEAD"])
        assert review.status == 0, review.stdout <> review.stderr
        assert review.stdout =~ "spec.review wrote"

        html = File.read!(Path.join(root, "_build/spec_review.html"))
        assert html =~ "spec/parse_error"
        assert html =~ "field: #{rejected_field}"
        refute html =~ ~s(<a href="#"></a>)
        refute html =~ ~s(<section class="subject" id="">)
        refute review.stderr =~ "** ("
      end
    end

    @tag spec: "ancora.parsing.structural_references"
    @tag spec: "ancora.gate.strict_verdict"
    test "a spec without metadata blocks both corpus gates and is not counted", %{root: root} do
      init_git_repo(root)

      write_files(root, %{
        "mix.exs" => """
        defmodule Fixture.MixProject do
          use Mix.Project
          def project, do: [app: :fixture, version: "0.1.0"]
        end
        """
      })

      write_spec(root, "missing-meta", """
      # Missing metadata

      ```yaml spec-requirements
      - id: missing.meta.requirement
        statement: This requirement has no subject metadata.
        priority: must
      ```
      """)

      commit_all(root, "missing metadata")

      check = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
      assert check.status == 1
      assert spec_finding_codes(check.stdout) == ["spec/missing_field"]
      assert check.stdout =~ "errors=1 warnings=0"

      assert check.stdout =~
               "[ERROR] .spec/specs/missing-meta.spec.md spec/missing_field .spec/specs/missing-meta.spec.md :: .spec/specs/missing-meta.spec.md: missing field spec-meta; add the required field"

      assert check.stdout =~ "checked subjects=0 requirements="
      assert List.last(output_lines(check.stdout)) =~ "spec.check result=fail tier=branch"

      validate = run_mix_subprocess(["spec.validate", "--root", root])
      assert validate.status == 1
      assert spec_finding_codes(validate.stdout) == ["spec/missing_field"]
      assert validate.stdout =~ "errors=1 warnings=0"

      assert validate.stdout =~
               "[ERROR] .spec/specs/missing-meta.spec.md spec/missing_field .spec/specs/missing-meta.spec.md :: .spec/specs/missing-meta.spec.md: missing field spec-meta; add the required field"

      assert validate.stdout =~ "checked subjects=0 requirements="
      assert List.last(output_lines(validate.stdout)) =~ "spec.validate result=fail tier=validate"

      for {args, heading} <- [
            {["spec.status", "--root", root], "Spec Led Status"},
            {[
               "run",
               "-e",
               "File.cd!(#{inspect(root)}, fn -> Mix.Tasks.Spec.Next.run([\"--base\", \"HEAD\"]) end)"
             ], "Spec Led Next"},
            {["spec.prime", "--root", root, "--base", "HEAD"], "Spec Led Prime"}
          ] do
        result = run_mix_subprocess(args)
        assert result.status == 0, result.stdout <> result.stderr
        assert result.stdout =~ heading
        refute result.stderr =~ "** ("
      end

      review = run_mix_subprocess(["spec.review", "--root", root, "--base", "HEAD"])
      assert review.status == 0, review.stdout <> review.stderr
      assert review.stdout =~ "spec.review wrote"
      refute review.stderr =~ "** ("

      write_spec(root, "missing-meta", """
      # Identified subject

      ```yaml spec-meta
      id: identified.subject
      kind: module
      status: active
      ```
      """)

      identified = run_mix_subprocess(["spec.check", "--root", root, "--base", "HEAD"])
      assert identified.stdout =~ "checked subjects=1 requirements="
    end
  end

  describe "field access" do
    @tag spec: "ancora.parsing.structural_references"
    test "reads schema structs and YAML maps without creating atoms" do
      meta = %Meta{id: "atom.subject", kind: "module", status: "active"}

      assert Index.field(meta, "id") == "atom.subject"
      assert Index.field(%{"id" => "string.subject"}, :id) == "string.subject"
      assert Index.subject_id(%{"meta" => meta}) == "atom.subject"
      assert Index.subject_id(%{"meta" => %{"id" => "string.subject"}}) == "string.subject"
      assert Index.subject_id(%{"meta" => nil}) == nil

      unknown = "unknown_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
      assert Index.field(%{nil => :wrong}, unknown) == nil
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
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

  defp spec_finding_codes(output) do
    ~r/(?:^|\s)(spec\/[a-z_]+)(?=\s)/
    |> Regex.scan(output, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp assert_rejected_meta_line(output, field) do
    assert Enum.any?(output_lines(output), fn line ->
             line =~ "[ERROR] - spec/parse_error .spec/specs/broken.spec.md ::" and
               line =~ "field: #{field}"
           end)
  end
end
