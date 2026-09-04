defmodule Ancora.AppendOnly do
  @moduledoc """
  Diff-time append-only detectors and statement-change disclosure. Exactly two guards:

    * `append/requirement_deleted` — a requirement id present at base is
      absent on HEAD
    * `append/must_downgraded` — a requirement's `priority` moves from
      `must` to `should`

  Either finding is suppressed only by an ADR with `status: accepted`
  whose `affects:` names the requirement id or its subject id. There is
  no weakening-class enum and no `change_type` requirement.

  `append/statement_changed` reports normalized statement changes at info.
  It is a disclosure, not a guard, and an ADR does not suppress it.

  `analyze/2` is a total function over `(prior_index, current_index)`.
  Both arguments are index-shaped maps (`"subjects"`, `"decisions"`).
  The module has no Git I/O.
  """

  alias Ancora.Finding

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
        if authorized?(decisions, id, prior.subject_id) do
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
          if must_to_should?(prior, current) and
               not authorized?(decisions, id, current.subject_id || prior.subject_id) do
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

  defp authorized?(decisions, requirement_id, subject_id) do
    Enum.any?(decisions, fn decision ->
      meta = fetch(decision, "meta")
      accepted?(meta) and names_target?(meta, requirement_id, subject_id)
    end)
  end

  defp accepted?(meta), do: fetch(meta, "status") == "accepted"

  defp names_target?(meta, requirement_id, subject_id) do
    affects = List.wrap(fetch(meta, "affects") || [])
    requirement_id in affects or (is_binary(subject_id) and subject_id in affects)
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
                 priority: fetch(req, "priority"),
                 statement: normalize_statement(fetch(req, "statement"))
               }}
            ]
        end
      end)
    end)
    |> Map.new()
  end

  defp subject_id(subject) do
    meta = fetch(subject, "meta")
    id = fetch(meta, "id") || fetch(subject, "id")
    if is_binary(id) and id != "", do: id, else: nil
  end

  defp list_field(map, key) do
    case fetch(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp id_of(item), do: fetch(item, "id")

  defp normalize_statement(statement) when is_binary(statement) do
    statement
    |> String.split()
    |> Enum.join(" ")
  end

  defp normalize_statement(_statement), do: ""

  defp fetch(nil, _key), do: nil

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    Map.get(map, key, if(atom_key, do: Map.get(map, atom_key)))
  end

  defp fetch(_, _), do: nil

  defp sort_findings(findings) do
    Enum.sort_by(findings, fn f ->
      {f.subject || "", f.code || "", f.message || ""}
    end)
  end
end
