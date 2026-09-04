defmodule Ancora.Finding do
  @moduledoc """
  Closed 33-code finding registry: the single source every other module reads.

  Each code has a family, a default severity, and a message function whose
  text names the subject or file and the action that clears the finding.
  Adding a code is a spec change in `ancora.findings`.
  """

  @enforce_keys [:code]
  defstruct [
    :code,
    :subject,
    :requirement,
    :file,
    :message,
    :severity,
    :severity_source
  ]

  @type severity :: :error | :warning | :info | :off
  @type source :: :config | :trailer | :ack | :default
  @type code :: String.t()

  @type t :: %__MODULE__{
          code: code(),
          subject: String.t() | nil,
          requirement: String.t() | nil,
          file: String.t() | nil,
          message: String.t() | nil,
          severity: severity() | nil,
          severity_source: source() | nil
        }

  @type entry :: %{
          family: String.t(),
          default: :error | :warning | :info,
          message: (map() -> String.t())
        }

  @non_tunable MapSet.new(["config/unknown_key", "config/invalid_value"])

  # {code, default}. Family is the prefix before `/`. Count is 33.
  @entries [
    {"derived/drift", :error},
    {"derived/drift_transitive", :info},
    {"derived/growth", :warning},
    {"derived/shrink", :warning},
    {"derived/unresolved_calls", :info},
    {"derived/unparseable_source", :error},
    {"derived/unanchored_subject", :warning},
    {"change/uncovered_file", :warning},
    {"change/missing_decision", :warning},
    {"tags/new_requirement_untagged", :warning},
    {"tags/tag_borrowed", :info},
    {"tags/parse_error", :error},
    {"tags/dynamic_value", :info},
    {"tags/requirement_untagged", :info},
    {"tags/unknown_requirement", :warning},
    {"append/requirement_deleted", :error},
    {"append/must_downgraded", :error},
    {"append/statement_changed", :info},
    {"format/retired_construct", :warning},
    {"spec/parse_error", :error},
    {"spec/duplicate_id", :error},
    {"spec/invalid_id", :error},
    {"spec/missing_field", :error},
    {"spec/unknown_reference", :error},
    {"spec/requirement_unverified", :info},
    {"adr/parse_error", :error},
    {"adr/missing_section", :error},
    {"adr/affects_empty", :warning},
    {"adr/affects_unresolved", :error},
    {"overlap/duplicate_covers", :error},
    {"overlap/must_stem_collision", :error},
    {"config/unknown_key", :warning},
    {"config/invalid_value", :warning}
  ]

  @codes Enum.map(@entries, &elem(&1, 0))
  @defaults Map.new(@entries)

  @doc "The closed registry: code → `%{family, default, message}`."
  @spec registry() :: %{optional(code()) => entry()}
  def registry do
    Map.new(@entries, fn {code, default} ->
      {code,
       %{
         family: family(code),
         default: default,
         message: fn ctx -> message(code, ctx) end
       }}
    end)
  end

  @doc "Every registry code, in declaration order."
  @spec codes() :: [code()]
  def codes, do: @codes

  @doc "True when `code` is in the registry."
  @spec known?(term()) :: boolean()
  def known?(code) when is_binary(code), do: Map.has_key?(@defaults, code)
  def known?(_), do: false

  @doc "Family prefix (`derived`, `spec`, …)."
  @spec family(code()) :: String.t()
  def family(code) when is_binary(code) do
    case String.split(code, "/", parts: 2) do
      [family, _rest] -> family
      [family] -> family
    end
  end

  @doc "Registry default severity for `code`."
  @spec default_severity(code()) :: :error | :warning | :info
  def default_severity(code) when is_binary(code) do
    Map.fetch!(@defaults, code)
  end

  @doc """
  False for `config/unknown_key` and `config/invalid_value`.

  Non-tunable codes ignore `severities:`, `overrides:`, and `Spec-Ack:`
  trailers so a misconfigured file cannot silence the config findings it
  itself produces.
  """
  @spec tunable?(code()) :: boolean()
  def tunable?(code) when is_binary(code), do: not MapSet.member?(@non_tunable, code)

  @doc "Builds a finding. `message` is rendered from `code` and `attrs` when omitted."
  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)
    code = Map.fetch!(attrs, :code)

    unless known?(code) do
      raise ArgumentError, "unknown finding code: #{inspect(code)}"
    end

    %__MODULE__{
      code: code,
      subject: Map.get(attrs, :subject),
      requirement: Map.get(attrs, :requirement),
      file: Map.get(attrs, :file),
      message: Map.get(attrs, :message) || message(code, attrs),
      severity: Map.get(attrs, :severity),
      severity_source: Map.get(attrs, :severity_source)
    }
  end

  @doc """
  Renders the designed message for `code`.

  Context keys used across codes: `:subject`, `:file`, `:requirement`,
  `:detail`, `:key`. Missing keys fall back to placeholders so the
  registry-closure test can call every message function.
  """
  @spec message(code(), map()) :: String.t()
  def message(code, ctx \\ %{}) when is_binary(code) and is_map(ctx) do
    render(code, ctx)
  end

  defp s(ctx), do: fetch(ctx, :subject, "unknown subject")
  defp f(ctx), do: fetch(ctx, :file, "unknown file")
  defp req(ctx), do: fetch(ctx, :requirement, "requirement")
  defp d(ctx, default), do: fetch(ctx, :detail, default)
  defp k(ctx), do: fetch(ctx, :key, fetch(ctx, :detail, "unknown key"))

  defp fetch(ctx, key, default) do
    case Map.get(ctx, key) do
      nil -> default
      value -> to_string(value)
    end
  end

  defp render("derived/drift", ctx) do
    "#{s(ctx)}: #{d(ctx, "production code")} changed (#{f(ctx)}) but the spec did not; " <>
      "edit the spec for this subject in the same diff"
  end

  defp render("derived/drift_transitive", ctx) do
    "#{s(ctx)}: #{d(ctx, "production code")} changed transitively (#{f(ctx)}); " <>
      "add the defining file to this subject's surface or review the change as informational"
  end

  defp render("derived/growth", ctx) do
    "#{s(ctx)}: tests now call new functions: #{d(ctx, "new functions")} — " <>
      "acknowledge them in the spec for this subject"
  end

  defp render("derived/shrink", ctx) do
    "#{s(ctx)}: tests stopped calling #{d(ctx, "removed functions")} — " <>
      "drop the dead contract from the spec or restore the coverage"
  end

  defp render("derived/unresolved_calls", ctx) do
    "#{s(ctx)}: calls not statically resolvable (#{f(ctx)} #{d(ctx, "calls")}); " <>
      "resolve the calls or leave this as visibility"
  end

  defp render("derived/unparseable_source", ctx) do
    "cannot parse #{f(ctx)} at base — drift comparison skipped; fix the parse"
  end

  defp render("derived/unanchored_subject", ctx) do
    "#{s(ctx)}: derived set is empty. Add tagged tests that call this subject's " <>
      "production code, or add a per-subject overrides: entry " <>
      "(code: derived/unanchored_subject, reason required) to acknowledge " <>
      "an integration-only subject."
  end

  defp render("change/uncovered_file", ctx) do
    "#{f(ctx)} changed; no subject's tests reach it — " <>
      "cover the file from a subject's tagged tests"
  end

  defp render("change/missing_decision", ctx) do
    "governance file #{f(ctx)} changed without a decision update; " <>
      "add or update an ADR in the same diff"
  end

  defp render("tags/new_requirement_untagged", ctx) do
    "#{s(ctx)}.#{req(ctx)}: added without a tagged test; tag a test with this requirement id"
  end

  defp render("tags/tag_borrowed", ctx) do
    "#{f(ctx)}: new test binds to unchanged requirement #{req(ctx)}; " <>
      "confirm the test exercises it"
  end

  defp render("tags/parse_error", ctx) do
    "#{f(ctx)}: test file failed tag scan (#{d(ctx, "parse error")}); fix the test file"
  end

  defp render("tags/dynamic_value", ctx) do
    "#{f(ctx)}: non-literal @tag spec: recorded, not guessed; use a literal requirement id"
  end

  defp render("tags/requirement_untagged", ctx) do
    "#{s(ctx)}.#{req(ctx)}: no tagged test; tag a test with this requirement id"
  end

  defp render("tags/unknown_requirement", ctx) do
    "#{f(ctx)}: @tag spec: names #{d(ctx, "unknown id")} which is not in the corpus; " <>
      "fix the tag or add the requirement"
  end

  defp render("append/requirement_deleted", ctx) do
    "#{s(ctx)}.#{req(ctx)} deleted; no authorizing ADR names it — " <>
      "add an accepted ADR whose affects: names the requirement or its subject"
  end

  defp render("append/must_downgraded", ctx) do
    "#{s(ctx)}.#{req(ctx)}: must → should; no authorizing ADR names it — " <>
      "add an accepted ADR whose affects: names the requirement or its subject"
  end

  defp render("append/statement_changed", ctx) do
    "#{s(ctx)}.#{req(ctx)}: requirement statement changed; review the revised contract"
  end

  defp render("format/retired_construct", ctx) do
    "#{f(ctx)}: retired construct #{d(ctx, "realized_by:/execute:")} on HEAD; " <>
      "remove realized_by:, execute:, or non-tagged_tests kinds"
  end

  defp render("spec/parse_error", ctx) do
    "#{f(ctx)}: spec parse error — #{d(ctx, "invalid YAML/structure")}; fix the block"
  end

  defp render("spec/duplicate_id", ctx) do
    "#{f(ctx)}: duplicate id #{d(ctx, "id")}; rename one so ids are unique"
  end

  defp render("spec/invalid_id", ctx) do
    "#{f(ctx)}: invalid id #{d(ctx, "id")}; fix the id format"
  end

  defp render("spec/missing_field", ctx) do
    "#{f(ctx)}: missing field #{d(ctx, "field")}; add the required field"
  end

  defp render("spec/unknown_reference", ctx) do
    "#{f(ctx)}: unknown reference #{d(ctx, "id")}; point it at an existing id"
  end

  defp render("spec/requirement_unverified", ctx) do
    "#{s(ctx)}.#{req(ctx)}: no tagged_tests verification block; " <>
      "add a tagged_tests block covering this requirement"
  end

  defp render("adr/parse_error", ctx) do
    "#{f(ctx)}: ADR parse error — #{d(ctx, "invalid frontmatter")}; fix frontmatter or sections"
  end

  defp render("adr/missing_section", ctx) do
    "#{f(ctx)}: missing section #{d(ctx, "section")}; add Context, Decision, or Consequences"
  end

  defp render("adr/affects_empty", ctx) do
    "#{f(ctx)}: ADR has empty affects:; name the requirement or subject ids this ADR authorizes"
  end

  defp render("adr/affects_unresolved", ctx) do
    "#{f(ctx)}: affects: names nonexistent id #{d(ctx, "id")}; fix the id"
  end

  defp render("overlap/duplicate_covers", ctx) do
    "#{s(ctx)}: duplicate covers #{d(ctx, "id")}; drop the duplicate cover"
  end

  defp render("overlap/must_stem_collision", ctx) do
    "#{s(ctx)}: must-stem collision #{d(ctx, "stem")}; rename one requirement"
  end

  defp render("config/unknown_key", ctx) do
    "#{f(ctx)}: unknown config key #{k(ctx)}; remove it or use a registry code"
  end

  defp render("config/invalid_value", ctx) do
    "#{f(ctx)}: invalid config value #{d(ctx, "entry")}; fix the value"
  end
end
