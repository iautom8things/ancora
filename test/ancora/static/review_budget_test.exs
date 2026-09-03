defmodule Ancora.Static.ReviewBudgetTest do
  use ExUnit.Case, async: true

  alias Ancora.Review.Html

  @tag spec: "ancora.review.size_budget"
  test "review rendering stays inside its line budget" do
    root = Path.expand("../../..", __DIR__)

    files =
      Path.wildcard(Path.join(root, "lib/ancora/review/*.ex")) ++
        [Path.join(root, "lib/ancora/markdown.ex")]

    counts = Map.new(files, &{&1, &1 |> File.stream!() |> Enum.count()})

    assert Enum.sum(Map.values(counts)) <= 5_000
    assert Enum.all?(counts, fn {_file, count} -> count <= 2_500 end)
  end

  @tag spec: "ancora.review.artifact_size"
  test "a 200-file review artifact stays below one megabyte" do
    changes =
      for index <- 1..200 do
        %{
          file: "lib/generated/file_#{index}.ex",
          lines: [{:add, "+  def value, do: #{index}"}]
        }
      end

    subjects =
      changes
      |> Enum.chunk_every(25)
      |> Enum.with_index(1)
      |> Enum.map(fn {subject_changes, index} ->
        review_subject(index, subject_changes, changes)
      end)

    view = %{
      meta: %{
        base_ref: "main",
        head_ref: "head",
        generated_at: ~U[2026-09-03 18:00:00Z],
        affected_subjects: 8,
        findings: 0
      },
      verdict: :pass,
      findings_delta: %{
        introduced: [],
        resolved: [],
        pre_existing: [],
        change_verdict: %{clean?: true}
      },
      triage: %{},
      subjects: subjects,
      decisions_changed: [],
      outside_changes: [],
      all_changes: changes,
      spec_health: %{subjects: 0, requirements: 0, errors: 0, warnings: 0}
    }

    artifact = view |> Html.render() |> IO.iodata_to_binary()

    assert byte_size(artifact) < 1_000_000
  end

  defp review_subject(index, owned_changes, all_changes) do
    owned_files = MapSet.new(owned_changes, & &1.file)

    %{
      id: "generated.#{index}",
      title: "Generated #{index}",
      summary: "Generated size-budget subject.",
      file: ".spec/specs/generated.#{index}.spec.md",
      requirements: [],
      scenarios: [],
      decision_refs: [],
      findings: [],
      spec_diff: %{},
      code: %{
        watched_interface:
          Enum.map(all_changes, fn change ->
            %{
              binding: "Generated.File#{index}.value/0",
              badge: :acknowledged,
              file: change.file,
              lines: if(MapSet.member?(owned_files, change.file), do: change.lines, else: [])
            }
          end),
        supporting_changes: [],
        test_changes: [],
        added_bindings: [],
        removed_bindings: []
      }
    }
  end
end
