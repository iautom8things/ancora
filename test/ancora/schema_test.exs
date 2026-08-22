Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.SchemaTest do
  use Ancora.TestCase

  alias Ancora.Schema
  alias Ancora.Schema.{Exception, Meta, Requirement, Scenario, Verification}

  describe "block structs" do
    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "validate_block accepts valid spec-meta as a Zoi-backed struct" do
      assert {:ok, meta} =
               Schema.validate_block("spec-meta", %{
                 "id" => "example.subject",
                 "kind" => "module",
                 "status" => "active",
                 "summary" => "preserved",
                 "decisions" => ["repo.policy"]
               })

      assert %Meta{} = meta
      assert meta.summary == "preserved"
      assert meta.decisions == ["repo.policy"]
      assert Schema.meta() == Meta.schema()
    end

    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "list-backed blocks accept valid items as structs" do
      assert {:ok, [%Requirement{id: "example.requirement"}]} =
               Schema.validate_block("spec-requirements", [
                 %{"id" => "example.requirement", "statement" => "Requirement"}
               ])

      assert {:ok, [%Scenario{id: "example.scenario"}]} =
               Schema.validate_block("spec-scenarios", [
                 %{
                   "id" => "example.scenario",
                   "covers" => ["example.requirement"],
                   "given" => ["given"],
                   "when" => ["when"],
                   "then" => ["then"]
                 }
               ])

      assert {:ok, [%Verification{kind: "tagged_tests"}]} =
               Schema.validate_block("spec-verification", [
                 %{"kind" => "tagged_tests", "covers" => ["example.requirement"]}
               ])

      assert {:ok, [%Exception{reason: "accepted"}]} =
               Schema.validate_block("spec-exceptions", [
                 %{
                   "id" => "example.exception",
                   "covers" => ["example.requirement"],
                   "reason" => "accepted"
                 }
               ])
    end

    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "rejects invalid identifiers including trailing newlines" do
      assert {:error, message} =
               Schema.validate_block("spec-meta", %{
                 "id" => "Bad Subject",
                 "kind" => "module",
                 "status" => "active"
               })

      assert message =~ "invalid id format"

      assert {:error, newline_message} =
               Schema.validate_block("spec-meta", %{
                 "id" => "example.subject\n",
                 "kind" => "module",
                 "status" => "active"
               })

      assert newline_message =~ "invalid id format"
    end
  end

  describe "retired constructs in schema" do
    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "realized_by of any shape is accepted without a tier schema" do
      assert {:ok, %Meta{realized_by: %{"shenanigans" => ["Foo"]}}} =
               Schema.validate_block("spec-meta", %{
                 "id" => "example.subject",
                 "kind" => "module",
                 "status" => "active",
                 "realized_by" => %{"shenanigans" => ["Foo"]}
               })

      assert {:ok, [%Requirement{realized_by: "not-a-map"}]} =
               Schema.validate_block("spec-requirements", [
                 %{
                   "id" => "example.req",
                   "statement" => "s",
                   "realized_by" => "not-a-map"
                 }
               ])
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "retired verification kinds and execute: are accepted" do
      for kind <- Verification.retired_kinds() do
        assert {:ok, [%Verification{kind: ^kind, execute: false}]} =
                 Schema.validate_block("spec-verification", [
                   %{
                     "kind" => kind,
                     "target" => "lib/example.ex",
                     "execute" => false,
                     "covers" => ["example.req"]
                   }
                 ])
      end
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "garbage verification kind is rejected naming the kind" do
      assert {:error, message} =
               Schema.validate_block("spec-verification", [
                 %{
                   "kind" => "bananas",
                   "covers" => ["example.req"]
                 }
               ])

      assert message =~ "bananas"
      assert message =~ "spec-verification[0]"
    end
  end
end
