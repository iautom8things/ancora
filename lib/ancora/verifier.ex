defmodule Ancora.Verifier do
  @moduledoc """
  Structural verifier: target/cover/duplicate/decision-ref checks.

  Emits `spec/unknown_reference`, `spec/duplicate_id`, `spec/invalid_id`,
  `spec/missing_field`, and `spec/requirement_unverified`. There is no
  command building, execution, timeout, forensics, or strength ladder.
  """

  alias Ancora.{Finding, Index}
  alias Ancora.Schema.Verification

  # \A/\z, not ^/$: `$` matches before a trailing newline.
  @id_pattern ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @meta_required ~w(id kind status)
  @requirement_required ~w(id statement)
  @scenario_required ~w(id covers given when then)

  @doc """
  Returns structural findings for `index`.

  `index` is the map produced by `Ancora.Index.build/2` (or a test
  double of that shape). Command machinery is not consulted.
  """
  @spec verify(map()) :: [Finding.t()]
  def verify(index) when is_map(index) do
    subjects = index["subjects"] || []
    decisions = index["decisions"] || []
    claim_ids = build_claim_ids(subjects)
    decision_ids = build_decision_ids(decisions)
    tagged_covers = tagged_tests_cover_ids(subjects)

    subject_findings =
      Enum.flat_map(subjects, fn subject ->
        verify_subject(subject, claim_ids, decision_ids, tagged_covers)
      end)

    (subject_findings ++
       duplicate_id_findings(subjects, decisions) ++
       invalid_declared_id_findings(subjects, decisions))
    |> sort_findings()
  end

  defp verify_subject(subject, claim_ids, decision_ids, tagged_covers) do
    file = Index.field(subject, "file")
    meta = Index.field(subject, "meta")
    subject_id = id_of(meta) || file
    requirements = map_items(list_field(subject, "requirements"))
    scenarios = map_items(list_field(subject, "scenarios"))
    verifications = map_items(list_field(subject, "verification"))

    []
    |> add_missing_fields(meta, @meta_required, subject_id, file, "spec-meta")
    |> add_requirement_missing_fields(requirements, subject_id, file)
    |> add_scenario_missing_fields(scenarios, subject_id, file)
    |> add_decision_reference_findings(meta, decision_ids, subject_id, file)
    |> add_cover_findings(scenarios, "scenario", claim_ids, subject_id, file)
    |> add_cover_findings(verifications, "verification", claim_ids, subject_id, file)
    |> add_requirement_unverified_findings(requirements, tagged_covers, subject_id, file)
  end

  defp add_missing_fields(findings, :rejected, _required, _subject_id, _file, "spec-meta"),
    do: findings

  defp add_missing_fields(findings, nil, _required, subject_id, file, "spec-meta") do
    [missing_field_finding(subject_id, file, "spec-meta") | findings]
  end

  defp add_missing_fields(findings, item, required, subject_id, file, _label) do
    Enum.reduce(required, findings, fn key, acc ->
      if present_required?(item, key) do
        acc
      else
        [missing_field_finding(subject_id, file, key) | acc]
      end
    end)
  end

  defp add_requirement_missing_fields(findings, requirements, subject_id, file) do
    Enum.reduce(requirements, findings, fn req, acc ->
      add_missing_fields(acc, req, @requirement_required, subject_id, file, "requirement")
    end)
  end

  defp add_scenario_missing_fields(findings, scenarios, subject_id, file) do
    Enum.reduce(scenarios, findings, fn scenario, acc ->
      add_missing_fields(acc, scenario, @scenario_required, subject_id, file, "scenario")
    end)
  end

  defp add_decision_reference_findings(findings, meta, decision_ids, subject_id, file) do
    meta
    |> list_field("decisions")
    |> Enum.reduce(findings, fn decision_id, acc ->
      cond do
        not is_binary(decision_id) ->
          acc

        not valid_id?(decision_id) ->
          [invalid_id_finding(subject_id, file, decision_id) | acc]

        MapSet.member?(decision_ids, decision_id) ->
          acc

        true ->
          [unknown_reference_finding(subject_id, file, decision_id) | acc]
      end
    end)
  end

  defp add_cover_findings(findings, items, kind, claim_ids, subject_id, file) do
    Enum.reduce(items, findings, fn item, acc ->
      item_id = id_of(item) || kind

      item
      |> list_field("covers")
      |> Enum.reduce(acc, fn cover_id, cover_acc ->
        cond do
          not is_binary(cover_id) ->
            cover_acc

          not valid_id?(cover_id) ->
            [invalid_id_finding(subject_id, file, cover_id) | cover_acc]

          MapSet.member?(claim_ids, cover_id) ->
            cover_acc

          true ->
            [unknown_reference_finding(subject_id, file, "#{item_id} -> #{cover_id}") | cover_acc]
        end
      end)
    end)
  end

  defp add_requirement_unverified_findings(
         findings,
         requirements,
         tagged_covers,
         subject_id,
         file
       ) do
    Enum.reduce(requirements, findings, fn req, acc ->
      req_id = id_of(req)

      if is_binary(req_id) and not MapSet.member?(tagged_covers, req_id) do
        [
          Finding.new(
            code: "spec/requirement_unverified",
            subject: subject_id,
            file: file,
            requirement: req_id,
            severity: Finding.default_severity("spec/requirement_unverified"),
            severity_source: :default
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp tagged_tests_cover_ids(subjects) do
    subjects
    |> Enum.flat_map(fn subject ->
      subject
      |> list_field("verification")
      |> Enum.filter(fn v -> Index.field(v, "kind") == Verification.current_kind() end)
      |> Enum.flat_map(&list_field(&1, "covers"))
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp duplicate_id_findings(subjects, decisions) do
    subject_entries = Enum.flat_map(subjects, &declared_ids(&1, :subject))
    requirement_entries = Enum.flat_map(subjects, &declared_ids(&1, "requirements"))
    scenario_entries = Enum.flat_map(subjects, &declared_ids(&1, "scenarios"))
    decision_entries = Enum.map(decisions, &decision_entry/1)

    (duplicate_findings(subject_entries) ++
       duplicate_findings(requirement_entries) ++
       duplicate_findings(scenario_entries) ++
       duplicate_findings(decision_entries))
    |> Enum.reject(&is_nil/1)
  end

  defp declared_ids(subject, :subject) do
    file = Index.field(subject, "file")
    id = subject_id(subject)
    if is_binary(id), do: [{id, file}], else: []
  end

  defp declared_ids(subject, key) do
    file = Index.field(subject, "file")

    subject
    |> list_field(key)
    |> Enum.flat_map(fn item ->
      case id_of(item) do
        id when is_binary(id) -> [{id, file}]
        _ -> []
      end
    end)
  end

  defp decision_entry(decision) do
    file = Index.field(decision, "file")
    id = decision_id(decision)
    if is_binary(id), do: {id, file}, else: {nil, file}
  end

  defp duplicate_findings(entries) do
    entries
    |> Enum.reject(fn
      {nil, _} -> true
      _ -> false
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {id, files} ->
      uniq_files = files |> Enum.reject(&is_nil/1) |> Enum.uniq()

      if length(files) > 1 do
        named = Enum.join(uniq_files, ", ")

        [
          Finding.new(
            code: "spec/duplicate_id",
            file: named,
            subject: id,
            detail: id,
            severity: Finding.default_severity("spec/duplicate_id"),
            severity_source: :default
          )
        ]
      else
        []
      end
    end)
  end

  defp invalid_declared_id_findings(subjects, decisions) do
    subject_ids =
      Enum.flat_map(subjects, fn subject ->
        file = Index.field(subject, "file")
        sid = subject_id(subject)

        ids =
          [{sid, sid, file}] ++
            Enum.map(list_field(subject, "requirements"), &{id_of(&1), sid, file}) ++
            Enum.map(list_field(subject, "scenarios"), &{id_of(&1), sid, file})

        Enum.flat_map(ids, fn
          {id, subject_id, file} when is_binary(id) ->
            if valid_id?(id), do: [], else: [invalid_id_finding(subject_id, file, id)]

          _ ->
            []
        end)
      end)

    decision_ids =
      Enum.flat_map(decisions, fn decision ->
        id = decision_id(decision)
        file = Index.field(decision, "file")

        if is_binary(id) and not valid_id?(id) do
          [invalid_id_finding(id, file, id)]
        else
          []
        end
      end)

    subject_ids ++ decision_ids
  end

  defp present_required?(item, key) do
    case Index.field(item, key) do
      nil -> false
      "" -> false
      list when is_list(list) -> list != []
      _other -> true
    end
  end

  defp valid_id?(id) when is_binary(id), do: Regex.match?(@id_pattern, id)
  defp valid_id?(_), do: false

  defp missing_field_finding(subject_id, file, field) do
    Finding.new(
      code: "spec/missing_field",
      subject: subject_id,
      file: file,
      detail: field,
      severity: Finding.default_severity("spec/missing_field"),
      severity_source: :default
    )
  end

  defp invalid_id_finding(subject_id, file, id) do
    Finding.new(
      code: "spec/invalid_id",
      subject: subject_id,
      file: file,
      detail: id,
      severity: Finding.default_severity("spec/invalid_id"),
      severity_source: :default
    )
  end

  defp unknown_reference_finding(subject_id, file, id) do
    Finding.new(
      code: "spec/unknown_reference",
      subject: subject_id,
      file: file,
      detail: id,
      severity: Finding.default_severity("spec/unknown_reference"),
      severity_source: :default
    )
  end

  defp build_claim_ids(subjects) do
    subjects
    |> Enum.flat_map(fn subject ->
      [subject_id(subject)] ++
        Enum.map(list_field(subject, "requirements"), &id_of/1) ++
        Enum.map(list_field(subject, "scenarios"), &id_of/1)
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp build_decision_ids(decisions) do
    decisions
    |> Enum.map(&decision_id/1)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp subject_id(subject) do
    Index.subject_id(subject)
  end

  defp decision_id(decision) do
    id_of(Index.field(decision, "meta"))
  end

  defp map_items(list) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp map_items(_), do: []

  defp list_field(map, key) do
    case Index.field(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp id_of(item), do: Index.field(item, "id")

  defp sort_findings(findings) do
    Enum.sort_by(findings, fn f ->
      {f.subject || "", f.file || "", f.code || "", f.message || ""}
    end)
  end
end
