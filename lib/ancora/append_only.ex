defmodule Ancora.AppendOnly do
  @moduledoc """
  Diff-time append-only detectors and statement-change disclosure. Exactly two guards:

    * `append/requirement_deleted` — a requirement id present at base is
      absent on HEAD
    * `append/must_downgraded` — a requirement's `priority` moves from
      `must` to `should`

  An accepted ADR's `affects:` authorizes either change only when it names
  the requirement id. For deletion, `retires:` may instead name the exact
  requirement or its subject. Retirement does not authorize a downgrade.
  There is no weakening-class enum and no `change_type` requirement.

  `append/statement_changed` reports normalized statement changes at info.
  It is a disclosure, not a guard, and an ADR does not suppress it.

  `analyze/2` is a total function over `(prior_index, current_index)`.
  Both arguments are index-shaped maps (`"subjects"`, `"decisions"`).
  The module has no Git I/O.
  """

  alias Ancora.{Finding, Index}

  @doc """
  Diffs `prior` against `current` and returns append-only guard findings plus
  statement-change disclosures.
  """
  @spec analyze(map(), map()) :: [Finding.t()]
  def analyze(prior, current) when is_map(prior) and is_map(current) do
    prior_reqs = requirements_by_id(prior)
    current_reqs = requirements_by_id(current)
    decisions = current["decisions"] || []

    (detect_requirement_deleted(prior_reqs, current_reqs, decisions) ++
       detect_must_downgraded(prior_reqs, current_reqs, decisions) ++
       detect_statement_changed(prior_reqs, current_reqs))
    |> sort_findings()
  end

  defp detect_requirement_deleted(prior_reqs, current_reqs, decisions) do
    Enum.flat_map(prior_reqs, fn {id, prior} ->
      if Map.has_key?(current_reqs, id) do
        []
      else
        if deletion_authorized?(decisions, id, prior.subject_id) do
          []
        else
          [requirement_deleted_finding(id, prior)]
        end
      end
    end)
  end

  defp detect_must_downgraded(prior_reqs, current_reqs, decisions) do
    Enum.flat_map(prior_reqs, fn {id, prior} ->
      case Map.fetch(current_reqs, id) do
        {:ok, current} ->
          if must_to_should?(prior, current) and not change_authorized?(decisions, id) do
            [must_downgraded_finding(id, prior)]
          else
            []
          end

        :error ->
          []
      end
    end)
  end

  defp must_to_should?(prior, current) do
    prior.priority == "must" and current.priority == "should"
  end

  defp detect_statement_changed(prior_reqs, current_reqs) do
    Enum.flat_map(prior_reqs, fn {id, prior} ->
      case Map.fetch(current_reqs, id) do
        {:ok, current} when prior.statement != current.statement ->
          [statement_changed_finding(id, current)]

        _ ->
          []
      end
    end)
  end

  defp deletion_authorized?(decisions, requirement_id, subject_id) do
    Enum.any?(decisions, fn decision ->
      meta = Index.field(decision, "meta")

      accepted?(meta) and
        (names_requirement?(meta, "affects", requirement_id) or
           names_retirement?(meta, requirement_id, subject_id))
    end)
  end

  defp change_authorized?(decisions, requirement_id) do
    Enum.any?(decisions, fn decision ->
      meta = Index.field(decision, "meta")
      accepted?(meta) and names_requirement?(meta, "affects", requirement_id)
    end)
  end

  defp accepted?(meta), do: Index.field(meta, "status") == "accepted"

  defp names_requirement?(meta, field, requirement_id) do
    requirement_id in List.wrap(Index.field(meta, field) || [])
  end

  defp names_retirement?(meta, requirement_id, subject_id) do
    retires = List.wrap(Index.field(meta, "retires") || [])
    requirement_id in retires or subject_id in retires
  end

  defp requirement_deleted_finding(id, prior) do
    Finding.new(
      code: "append/requirement_deleted",
      subject: prior.subject_id,
      requirement: id,
      severity: Finding.default_severity("append/requirement_deleted"),
      severity_source: :default
    )
  end

  defp must_downgraded_finding(id, prior) do
    Finding.new(
      code: "append/must_downgraded",
      subject: prior.subject_id,
      requirement: id,
      severity: Finding.default_severity("append/must_downgraded"),
      severity_source: :default
    )
  end

  defp statement_changed_finding(id, current) do
    Finding.new(
      code: "append/statement_changed",
      subject: current.subject_id,
      requirement: id,
      severity: Finding.default_severity("append/statement_changed"),
      severity_source: :default
    )
  end

  defp requirements_by_id(index) do
    (index["subjects"] || [])
    |> Enum.flat_map(fn subject ->
      subject_id = subject_id(subject)

      subject
      |> list_field("requirements")
      |> Enum.flat_map(fn req ->
        case id_of(req) do
          nil ->
            []

          id ->
            [
              {id,
               %{
                 id: id,
                 subject_id: subject_id,
                 priority: Index.field(req, "priority"),
                 statement: normalize_statement(Index.field(req, "statement"))
               }}
            ]
        end
      end)
    end)
    |> Map.new()
  end

  defp subject_id(subject), do: Index.subject_id(subject)

  defp list_field(map, key) do
    case Index.field(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp id_of(item), do: Index.field(item, "id")

  defp normalize_statement(statement) when is_binary(statement) do
    statement
    |> String.split()
    |> Enum.join(" ")
  end

  defp normalize_statement(_statement), do: ""

  defp sort_findings(findings) do
    Enum.sort_by(findings, fn f ->
      {f.subject || "", f.code || "", f.message || ""}
    end)
  end
end
