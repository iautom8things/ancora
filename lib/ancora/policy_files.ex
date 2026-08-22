defmodule Ancora.PolicyFiles do
  @moduledoc """
  File-kind classification and the governance-file set for `change/missing_decision`.

  ## Governance files

  These paths count as governance. A change to any of them, with no
  `.spec/decisions/` file added or changed in the same diff, is what
  `change/missing_decision` fires on:

    * `.spec/specs/**` — authored subject specs
    * `.spec/config.yml` — gate config
    * `.spec/AGENTS.md` — agent guidance
    * `.spec/README.md` — corpus README

  `.spec/decisions/**` is the ADR set that satisfies the co-change rule
  (except `README.md` in that directory, which is documentation, not an
  ADR). Decision files themselves are not governance files: editing an
  ADR does not require a second ADR.

  `missing_decision?/1` is the boolean form of that rule over a list of
  repo-relative changed paths.
  """

  @type kind :: :lib | :test | :doc | :generated | :unknown
  @type severity :: :off | :info | :warning | :error
  @type co_change_rule ::
          {:requires_subject_touch, severity()}
          | :test_only_allowed
          | :doc_only_allowed
          | :ignored
          | :unknown_escalates

  @test_prefixes ~w(test/ test_support/)
  @doc_prefixes ~w(docs/ guides/)
  @doc_root_files ~w(README.md AGENTS.md CHANGELOG.md LICENSE NOTICE)
  @lib_prefixes ~w(lib/ skills/)
  @lib_root_files ~w(mix.exs)
  @plan_doc_prefix "docs/plans/"
  @governance_root_files ~w(.spec/config.yml .spec/AGENTS.md .spec/README.md)
  @specs_prefix ".spec/specs/"
  @decisions_prefix ".spec/decisions/"

  @doc "Classifies a repo-relative path into a file kind."
  @spec classify(String.t()) :: kind()
  def classify(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "priv/plts/") -> :generated
      String.starts_with?(path, "priv/") -> :lib
      starts_with_any?(path, @test_prefixes) -> :test
      governance?(path) -> :doc
      starts_with_any?(path, @doc_prefixes) -> :doc
      path in @doc_root_files -> :doc
      starts_with_any?(path, @lib_prefixes) -> :lib
      path in @lib_root_files -> :lib
      true -> :unknown
    end
  end

  @doc """
  Returns the co-change rule that applies to a kind or path.

  Branch-local `docs/plans/` paths short-circuit to `:ignored` regardless of
  their `:doc` classification.
  """
  @spec co_change_rule(kind() | String.t()) :: co_change_rule()
  def co_change_rule(path) when is_binary(path) do
    cond do
      String.starts_with?(path, @plan_doc_prefix) -> :ignored
      true -> co_change_rule(classify(path))
    end
  end

  def co_change_rule(:lib), do: {:requires_subject_touch, :error}
  def co_change_rule(:test), do: :test_only_allowed
  def co_change_rule(:doc), do: :doc_only_allowed
  def co_change_rule(:generated), do: :ignored
  def co_change_rule(:unknown), do: :unknown_escalates

  @doc """
  Returns true when a path participates in co-change gating.

  Paths with rule `:ignored` (generated, or branch-local `docs/plans/`) are
  excluded. Paths with rule `:unknown_escalates` are also excluded from the
  gate itself; callers that want to surface unknowns can do so via a separate
  finding using `co_change_rule/1` directly.
  """
  @spec policy_target?(String.t()) :: boolean()
  def policy_target?(path) when is_binary(path) do
    case co_change_rule(path) do
      :ignored -> false
      :unknown_escalates -> false
      _ -> true
    end
  end

  @doc "True when `path` is in the governance-file set."
  @spec governance?(String.t()) :: boolean()
  def governance?(path) when is_binary(path) do
    path in @governance_root_files or String.starts_with?(path, @specs_prefix)
  end

  @doc "True when `path` is an ADR under `.spec/decisions/` (not README.md)."
  @spec decision_file?(String.t()) :: boolean()
  def decision_file?(path) when is_binary(path) do
    String.starts_with?(path, @decisions_prefix) and Path.basename(path) != "README.md"
  end

  @doc """
  True when a governance file changed and no ADR in `.spec/decisions/`
  was added or changed in the same path set. That is the
  `change/missing_decision` trigger.
  """
  @spec missing_decision?([String.t()]) :: boolean()
  def missing_decision?(changed_paths) when is_list(changed_paths) do
    Enum.any?(changed_paths, &governance?/1) and not Enum.any?(changed_paths, &decision_file?/1)
  end

  defp starts_with_any?(path, prefixes), do: Enum.any?(prefixes, &String.starts_with?(path, &1))
end
