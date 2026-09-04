defmodule Ancora.Review do
  @moduledoc "Builds the data model for the self-contained spec review artifact."

  alias Ancora.BaseView
  alias Ancora.Derive
  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership
  alias Ancora.Derive.ModuleLocator
  alias Ancora.Derive.RunContext
  alias Ancora.Gate
  alias Ancora.Gate.Preflight
  alias Ancora.Git
  alias Ancora.Index
  alias Ancora.Output.Verdict
  alias Ancora.Review.FileDiff
  alias Ancora.Review.FindingsDelta
  alias Ancora.Review.SpecDiff
  alias Ancora.SubjectFiles
  alias Ancora.TagScanner

  @diff_families ~w(derived change append)

  @spec build(Path.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def build(root, opts \\ []) when is_binary(root) do
    with {:ok, preflight} <- Preflight.run(root, opts),
         {:ok, context} <- RunContext.start(preflight.root, preflight.base) do
      try do
        build_with_context(preflight, context, opts)
      after
        RunContext.stop(context)
      end
    end
  end

  @doc "Compatibility entry point for callers that already hold the parsed index."
  @spec build_view(map(), Path.t(), keyword()) :: map()
  def build_view(_index, root, opts \\ []) do
    case build(root, opts) do
      {:ok, view} -> view
      {:env, message} -> raise ArgumentError, message
    end
  end

  defp build_with_context(preflight, context, opts) do
    with {:ok, change_set} <- ChangeSet.compute(context),
         {:ok, base_root} <- BaseView.materialize(context),
         {:ok, gate_report} <- gate_report(preflight, change_set, opts) do
      try do
        {:ok, assemble(preflight, change_set, base_root, gate_report, opts)}
      after
        File.rm_rf(base_root)
      end
    else
      {:env, _message} = error -> error
      {:error, reason} -> raise "review assembly failed: #{inspect(reason)}"
    end
  end

  defp gate_report(preflight, change_set, opts) do
    index = Index.build(preflight.root, index_opts(opts))

    if ChangeSet.paths(change_set) == [] and index["subjects"] == [] do
      {:ok,
       %{
         all_findings: [],
         checked: %{subjects: 0, requirements: 0, errors: 0, warnings: 0}
       }}
    else
      Gate.check(preflight.root, opts)
    end
  end

  defp assemble(preflight, change_set, base_root, gate_report, opts) do
    index_opts = index_opts(opts)
    head_index = Index.build(preflight.root, index_opts)
    base_index = Index.build(base_root, index_opts)
    changed_files = ChangeSet.paths(change_set)
    diffs = FileDiff.for_files(preflight.root, preflight.base, changed_files)
    all_findings = gate_report.all_findings
    diff_findings = Enum.filter(all_findings, &diff_scoped?/1)

    findings_delta =
      FindingsDelta.classify(
        FindingsDelta.repo_findings(base_index),
        FindingsDelta.repo_findings(head_index),
        diff_findings
      )

    tags = tagged_test_files(preflight)
    {subject_sets, footprints} = derive_subjects(preflight, change_set, tags)
    file_owners = file_owners(footprints)

    subjects =
      subjects(
        head_index,
        base_index,
        preflight.root,
        changed_files,
        diffs,
        tags,
        subject_sets,
        footprints,
        file_owners,
        all_findings
      )

    decisions = decisions(head_index, changed_files)

    %{
      meta: %{
        base_ref: preflight.base,
        head_ref: head_ref(preflight.root),
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        affected_subjects: length(subjects),
        findings: length(all_findings)
      },
      verdict: if(Verdict.pass?(gate_report), do: :pass, else: :fail),
      findings_delta: findings_delta,
      triage: Enum.group_by(findings_delta.introduced, &(&1.severity || :info)),
      subjects: subjects,
      decisions_changed: decisions,
      outside_changes: outside_changes(changed_files, subjects, decisions),
      all_changes: Enum.map(changed_files, &%{file: &1, lines: Map.get(diffs, &1, [])}),
      spec_health: gate_report.checked
    }
  end

  defp subjects(
         head_index,
         base_index,
         root,
         changed_files,
         diffs,
         tags,
         subject_sets,
         footprints,
         file_owners,
         findings
       ) do
    base_by_id = Map.new(base_index["subjects"] || [], &{subject_id(&1), &1})

    head_index["subjects"]
    |> Enum.filter(&is_binary(subject_id(&1)))
    |> Enum.map(fn subject ->
      id = subject_id(subject)
      subject_findings = Enum.filter(findings, &(&1.subject == id))
      spec_file = subject["file"]
      test_files = Map.get(tags, id, [])
      drift_cards = drift_cards(subject_findings, diffs)

      called =
        subject_sets
        |> Map.get(id, %{})
        |> Derive.all_bindings()
        |> Enum.map(&review_binding/1)
        |> MapSet.new()

      acknowledged_cards =
        acknowledged_cards(root, called, changed_files, diffs, drift_cards)

      watched_cards = drift_cards ++ acknowledged_cards
      watched_files = watched_cards |> Enum.map(& &1.file) |> MapSet.new()

      changed_tests =
        Enum.filter(test_files, &(&1 in changed_files and Map.get(file_owners, &1) == id))

      supporting =
        footprints
        |> Map.get(id, MapSet.new())
        |> MapSet.intersection(MapSet.new(changed_files))
        |> Enum.filter(&(Map.get(file_owners, &1) == id))
        |> Enum.reject(
          &(&1 == spec_file or &1 in changed_tests or MapSet.member?(watched_files, &1))
        )
        |> Enum.filter(&source_file?/1)
        |> Enum.sort()

      %{
        id: id,
        title: subject["title"] || id,
        summary: meta_field(subject, :summary, ""),
        file: spec_file,
        requirements: subject["requirements"] || [],
        scenarios: subject["scenarios"] || [],
        decision_refs: meta_field(subject, :decisions, []),
        findings: subject_findings,
        spec_diff: SpecDiff.compute(subject, Map.get(base_by_id, id)),
        code: %{
          watched_interface: watched_cards,
          supporting_changes: Enum.map(supporting, &%{file: &1, lines: Map.get(diffs, &1, [])}),
          test_changes: Enum.map(changed_tests, &%{file: &1, lines: Map.get(diffs, &1, [])}),
          added_bindings: binding_delta(subject_findings, "derived/growth"),
          removed_bindings: binding_delta(subject_findings, "derived/shrink")
        }
      }
    end)
    |> Enum.filter(&affected?(&1, changed_files))
    |> Enum.sort_by(& &1.id)
    |> scope_watched_diffs(file_owners)
  end

  defp scope_watched_diffs(subjects, file_owners) do
    watched_owners = watched_file_owners(subjects, file_owners)

    subjects
    |> Enum.map_reduce(MapSet.new(), fn subject, carried_files ->
      {watched_interface, carried_files} =
        Enum.map_reduce(subject.code.watched_interface, carried_files, fn card, carried_files ->
          if Map.fetch!(watched_owners, card.file) == subject.id and
               not MapSet.member?(carried_files, card.file) do
            {card, MapSet.put(carried_files, card.file)}
          else
            {%{card | lines: []}, carried_files}
          end
        end)

      {%{subject | code: %{subject.code | watched_interface: watched_interface}}, carried_files}
    end)
    |> elem(0)
  end

  defp watched_file_owners(subjects, file_owners) do
    Enum.reduce(subjects, %{}, fn subject, watched_owners ->
      Enum.reduce(subject.code.watched_interface, watched_owners, fn card, watched_owners ->
        Map.put_new(watched_owners, card.file, Map.get(file_owners, card.file, subject.id))
      end)
    end)
  end

  defp affected?(subject, changed_files) do
    subject.file in changed_files or subject.findings != [] or
      subject.code.watched_interface != [] or subject.code.supporting_changes != [] or
      subject.code.test_changes != []
  end

  defp drift_cards(findings, diffs) do
    findings
    |> Enum.filter(&(&1.code == "derived/drift"))
    |> Enum.map(fn finding ->
      %{
        binding: binding_from_message(finding.message),
        badge: if(finding.severity_source == :ack, do: :acknowledged, else: :drift),
        file: finding.file,
        lines: Map.get(diffs, finding.file, [])
      }
    end)
  end

  defp acknowledged_cards(root, called, changed_files, diffs, drift_cards) do
    watched = MapSet.new(drift_cards, & &1.binding)

    changed_files
    |> Enum.filter(&String.starts_with?(&1, "lib/"))
    |> Enum.flat_map(fn file ->
      module = source_module(root, file)

      diffs
      |> Map.get(file, [])
      |> changed_definitions(module)
      |> Enum.filter(&MapSet.member?(called, &1))
      |> Enum.reject(&MapSet.member?(watched, format_binding(&1)))
      |> Enum.map(fn binding ->
        %{
          binding: format_binding(binding),
          badge: :acknowledged,
          file: file,
          lines: Map.get(diffs, file, [])
        }
      end)
    end)
    |> Enum.uniq_by(& &1.binding)
  end

  defp derive_subjects(preflight, change_set, tags) do
    with {:ok, locator} <- ModuleLocator.build(preflight.project, change_set),
         {:ok, indexes} <- definition_indexes(preflight.root, locator),
         membership = %Membership{head: ModuleLocator.modules(locator, :head)},
         {:ok, context} <- Derive.context({:ok, membership}, :head, indexes),
         {:ok, sets} <-
           Derive.run(tags,
             side: :head,
             context: context,
             sources: &File.read(Path.join(preflight.root, &1))
           ) do
      {sets, SubjectFiles.build(sets, locator)}
    else
      _error -> {%{}, %{}}
    end
  end

  defp definition_indexes(root, locator) do
    locator.head
    |> Map.values()
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, indexes} ->
      with {:ok, source} <- File.read(Path.join(root, path)),
           {:ok, index} <- DefIndex.build(source, path) do
        {:cont, {:ok, Map.put(indexes, path, index)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, by_path} ->
        {:ok, Map.new(locator.head, fn {module, path} -> {module, Map.fetch!(by_path, path)} end)}

      {:error, _reason} = error ->
        error
    end
  end

  defp file_owners(footprints) do
    footprints
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {subject_id, files}, owners ->
      Enum.reduce(files, owners, &Map.put_new(&2, &1, subject_id))
    end)
  end

  defp source_module(root, file) do
    with {:ok, source} <- File.read(Path.join(root, file)),
         [module] <-
           Regex.run(~r/\bdefmodule\s+([A-Z][A-Za-z0-9_.]*)/, source, capture: :all_but_first) do
      module
    else
      _ -> nil
    end
  end

  defp changed_definitions(lines, nil), do: Enum.take(lines, 0)

  defp changed_definitions(lines, module) do
    lines
    |> Enum.filter(fn {kind, _line} -> kind in [:add, :del] end)
    |> Enum.flat_map(fn {_kind, line} ->
      case Regex.run(
             ~r/\bdef(?:macro|guard|delegate)?\s+([a-zA-Z_][a-zA-Z0-9_!?]*)(?:\(([^)]*)\))?/,
             line,
             capture: :all_but_first
           ) do
        [name, arguments] -> [{module, name, argument_count(arguments)}]
        [name] -> [{module, name, 0}]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp argument_count(arguments) do
    case String.trim(arguments) do
      "" -> 0
      value -> value |> String.split(",") |> length()
    end
  end

  defp format_binding({module, name, arity}), do: "#{module}.#{name}/#{arity}"

  defp review_binding({module, name, arity}) do
    module = module |> Atom.to_string() |> String.trim_leading("Elixir.")
    {module, Atom.to_string(name), arity}
  end

  defp binding_from_message(message) do
    case Regex.run(~r/([A-Z][A-Za-z0-9_.]*\.[a-zA-Z_!?][a-zA-Z0-9_!?]*\/\d+)/, message || "",
           capture: :all_but_first
         ) do
      [binding] -> binding
      _ -> "changed binding"
    end
  end

  defp binding_delta(findings, code) do
    findings
    |> Enum.filter(&(&1.code == code))
    |> Enum.flat_map(fn finding ->
      Regex.scan(~r/[A-Z][A-Za-z0-9_.]*\.[a-zA-Z_!?][a-zA-Z0-9_!?]*\/\d+/, finding.message || "")
      |> List.flatten()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp tagged_test_files(preflight) do
    paths = Enum.map(preflight.config.test_paths, &Path.join(preflight.root, &1))

    case TagScanner.scan(paths) do
      {:ok, tag_map, _errors, _dynamic} ->
        tag_map
        |> TagScanner.fold_to_subjects()
        |> Map.new(fn {id, entries} ->
          files = entries |> Enum.map(&Path.relative_to(&1.file, preflight.root)) |> Enum.uniq()
          {id, files}
        end)

      _ ->
        %{}
    end
  end

  defp decisions(index, changed_files) do
    index["decisions"]
    |> List.wrap()
    |> Enum.filter(&(&1["file"] in changed_files))
    |> Enum.map(fn decision ->
      %{id: decision_id(decision), title: decision["title"], file: decision["file"]}
    end)
  end

  defp outside_changes(changed_files, subjects, decisions) do
    mapped =
      subjects
      |> Enum.flat_map(fn subject ->
        [subject.file] ++
          Enum.map(subject.code.watched_interface, & &1.file) ++
          Enum.map(subject.code.supporting_changes, & &1.file) ++
          Enum.map(subject.code.test_changes, & &1.file)
      end)
      |> Kernel.++(Enum.map(decisions, & &1.file))
      |> MapSet.new()

    Enum.reject(changed_files, &MapSet.member?(mapped, &1))
  end

  defp diff_scoped?(finding) do
    family = finding.code |> String.split("/", parts: 2) |> List.first()
    family in @diff_families
  end

  defp source_file?(path), do: String.starts_with?(path, ["lib/", "test/"])

  defp subject_id(subject), do: Index.subject_id(subject)

  defp meta_field(subject, key, default) do
    case subject["meta"] do
      nil -> default
      meta -> Map.get(meta, key) || default
    end
  end

  defp decision_id(%{"meta" => meta}) when is_map(meta), do: Map.get(meta, "id")
  defp decision_id(_decision), do: nil

  defp head_ref(root) do
    case Git.run(root, ["rev-parse", "HEAD"]) do
      {:ok, oid} -> String.trim(oid)
      {:error, _reason} -> "HEAD"
    end
  end

  defp index_opts(opts) do
    case Keyword.get(opts, :spec_dir) do
      nil -> []
      spec_dir -> [spec_dir: spec_dir]
    end
  end
end
