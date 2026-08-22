defmodule Ancora.Overlap do
  @moduledoc """
  Head-only semantic-overlap detector for authored `.spec/` content.

  `analyze/1` is a total pure function over the head-side subject list.
  It consults nothing outside that argument — no state delta, no Git I/O.

  Emits two finding codes:

    * `overlap/duplicate_covers` when two verification entries in the
      corpus have identical `covers:` lists
    * `overlap/must_stem_collision` when two `must` requirements in one
      subject share a normalized stem
  """

  alias Ancora.Finding

  @doc """
  Returns overlap findings for `subjects`.

  Identical inputs return equal findings lists.
  """
  @spec analyze([map()]) :: [Finding.t()]
  def analyze(subjects) when is_list(subjects) do
    (detect_duplicate_covers(subjects) ++ detect_must_stem_collision(subjects))
    |> sort_findings()
  end

  defp detect_duplicate_covers(subjects) do
    entries =
      Enum.flat_map(subjects, fn subject ->
        subject_id = subject_id(subject)
        file = fetch(subject, "file")

        subject
        |> list_field("verification")
        |> Enum.with_index()
        |> Enum.flat_map(fn {verification, idx} ->
          covers = list_field(verification, "covers")

          if covers == [] do
            []
          else
            [
              %{
                subject_id: subject_id,
                file: file,
                covers: covers,
                index: idx
              }
            ]
          end
        end)
      end)

    entries
    |> Enum.group_by(& &1.covers)
    |> Enum.flat_map(fn {_covers, group} ->
      if length(group) > 1 do
        [duplicate_covers_finding(group)]
      else
        []
      end
    end)
  end

  defp detect_must_stem_collision(subjects) do
    subjects
    |> Enum.flat_map(fn subject ->
      subject_id = subject_id(subject)
      file = fetch(subject, "file")

      subject
      |> list_field("requirements")
      |> Enum.filter(&must?/1)
      |> Enum.group_by(&canonical_stem/1)
      |> Enum.flat_map(fn {stem, reqs} ->
        ids =
          reqs
          |> Enum.map(&id_of/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        case ids do
          [_, _ | _] -> [must_stem_collision_finding(subject_id, file, stem, ids)]
          _ -> []
        end
      end)
    end)
  end

  defp duplicate_covers_finding(group) do
    named =
      group
      |> Enum.map(fn entry ->
        "#{entry.subject_id || "<unknown>"} verification[#{entry.index}]"
      end)
      |> Enum.sort()
      |> Enum.join(", ")

    file = group |> Enum.map(& &1.file) |> Enum.find(&is_binary/1)
    subject_id = group |> Enum.map(& &1.subject_id) |> Enum.find(&is_binary/1)

    Finding.new(
      code: "overlap/duplicate_covers",
      subject: subject_id,
      file: file,
      detail: named,
      severity: Finding.default_severity("overlap/duplicate_covers"),
      severity_source: :default
    )
  end

  defp must_stem_collision_finding(subject_id, file, stem, req_ids) do
    Finding.new(
      code: "overlap/must_stem_collision",
      subject: subject_id,
      file: file,
      detail: stem,
      requirement: List.first(req_ids),
      severity: Finding.default_severity("overlap/must_stem_collision"),
      severity_source: :default
    )
  end

  defp must?(req) do
    case fetch(req, "priority") do
      "must" -> true
      :must -> true
      _ -> false
    end
  end

  defp canonical_stem(req) do
    statement = fetch(req, "statement") || ""

    normalized =
      statement
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[[:punct:]]+/u, " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    case Regex.run(~r/\b(must not|shall not|must|shall|should|may)\b(.*)/, normalized) do
      [_, modal, rest] -> String.trim(modal <> rest)
      _ -> normalized
    end
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
      {f.subject || "", f.file || "", f.code || ""}
    end)
  end
end
