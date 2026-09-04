defmodule Ancora.FindingTest do
  use ExUnit.Case, async: true

  alias Ancora.Finding

  @expected_codes [
    "derived/drift",
    "derived/drift_transitive",
    "derived/growth",
    "derived/shrink",
    "derived/unresolved_calls",
    "derived/unparseable_source",
    "derived/unanchored_subject",
    "change/uncovered_file",
    "change/missing_decision",
    "tags/new_requirement_untagged",
    "tags/parse_error",
    "tags/dynamic_value",
    "tags/requirement_untagged",
    "tags/unknown_requirement",
    "append/requirement_deleted",
    "append/must_downgraded",
    "format/retired_construct",
    "spec/parse_error",
    "spec/duplicate_id",
    "spec/invalid_id",
    "spec/missing_field",
    "spec/unknown_reference",
    "spec/requirement_unverified",
    "adr/parse_error",
    "adr/missing_section",
    "adr/affects_empty",
    "adr/affects_unresolved",
    "overlap/duplicate_covers",
    "overlap/must_stem_collision",
    "config/unknown_key",
    "config/invalid_value"
  ]

  @expected_defaults %{
    "derived/drift" => :error,
    "derived/drift_transitive" => :info,
    "derived/growth" => :warning,
    "derived/shrink" => :warning,
    "derived/unresolved_calls" => :info,
    "derived/unparseable_source" => :error,
    "derived/unanchored_subject" => :warning,
    "change/uncovered_file" => :warning,
    "change/missing_decision" => :warning,
    "tags/new_requirement_untagged" => :warning,
    "tags/parse_error" => :error,
    "tags/dynamic_value" => :info,
    "tags/requirement_untagged" => :info,
    "tags/unknown_requirement" => :warning,
    "append/requirement_deleted" => :error,
    "append/must_downgraded" => :error,
    "format/retired_construct" => :warning,
    "spec/parse_error" => :error,
    "spec/duplicate_id" => :error,
    "spec/invalid_id" => :error,
    "spec/missing_field" => :error,
    "spec/unknown_reference" => :error,
    "spec/requirement_unverified" => :info,
    "adr/parse_error" => :error,
    "adr/missing_section" => :error,
    "adr/affects_empty" => :warning,
    "adr/affects_unresolved" => :error,
    "overlap/duplicate_covers" => :error,
    "overlap/must_stem_collision" => :error,
    "config/unknown_key" => :warning,
    "config/invalid_value" => :warning
  }

  describe "registry closure" do
    @tag spec: "ancora.findings.registry_closed"
    test "owns exactly the 31 enumerated codes, each with family, default, and message" do
      registry = Finding.registry()
      codes = Finding.codes()

      assert length(codes) == 31
      assert length(Enum.uniq(codes)) == 31
      assert codes == @expected_codes
      assert Map.keys(registry) -- @expected_codes == []
      assert @expected_codes -- Map.keys(registry) == []

      for {code, entry} <- registry do
        assert is_binary(entry.family) and entry.family != "",
               "#{code} is missing family"

        assert entry.default in [:error, :warning, :info],
               "#{code} is missing a default severity"

        assert is_function(entry.message, 1),
               "#{code} is missing a message function"

        message =
          entry.message.(%{
            subject: "example.subject",
            file: "lib/example.ex",
            requirement: "example.subject.req",
            detail: "detail",
            key: "key"
          })

        assert is_binary(message) and String.trim(message) != "",
               "#{code} message function returned an empty string"
      end
    end

    @tag spec: "ancora.findings.registry_closed"
    test "new/1 rejects a code that is not in the registry" do
      assert_raise ArgumentError, ~r/unknown finding code/, fn ->
        Finding.new(code: "branch_guard_realization_drift")
      end
    end
  end

  describe "registry defaults" do
    @tag spec: "ancora.findings.registry_defaults"
    test "each code's default matches the spec table" do
      assert map_size(@expected_defaults) == 31

      for {code, expected} <- @expected_defaults do
        assert Finding.default_severity(code) == expected,
               "#{code} default is #{inspect(Finding.default_severity(code))}, expected #{inspect(expected)}"
      end
    end
  end

  describe "messages carry remedy" do
    @tag spec: "ancora.findings.messages_carry_remedy"
    test "every message names the subject or file and an action that clears the finding" do
      ctx = %{
        subject: "billing.core",
        file: "lib/billing.ex",
        requirement: "billing.core.charge",
        detail: "Billing.charge/1",
        key: "test_tags"
      }

      for code <- Finding.codes() do
        message = Finding.message(code, ctx)

        names_concern =
          String.contains?(message, ctx.subject) or String.contains?(message, ctx.file)

        assert names_concern,
               "#{code} message names neither subject nor file: #{inspect(message)}"

        assert String.trim(message) != ""
      end
    end

    @tag spec: "ancora.findings.messages_carry_remedy"
    test "derived/unanchored_subject names overrides: and the subject id" do
      message =
        Finding.message("derived/unanchored_subject", %{subject: "atlas.web.sessions"})

      assert message =~ "atlas.web.sessions"
      assert message =~ "overrides:"
    end
  end

  describe "non-tunable codes" do
    @tag spec: "ancora.findings.config_schema"
    test "config/unknown_key and config/invalid_value are not tunable" do
      refute Finding.tunable?("config/unknown_key")
      refute Finding.tunable?("config/invalid_value")
      assert Finding.tunable?("derived/drift")
    end
  end
end
