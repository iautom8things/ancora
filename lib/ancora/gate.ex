defmodule Ancora.Gate do
  @moduledoc """
  Assembles preflight, corpus, diff, derivation, comparison, and finding stages.
  """

  alias Ancora.AppendOnly
  alias Ancora.BaseView
  alias Ancora.ChangeAnalysis
  alias Ancora.Derive
  alias Ancora.Derive.Ack
  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.Compare
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership
  alias Ancora.Derive.ModuleLocator
  alias Ancora.Derive.RunContext
  alias Ancora.Finding
  alias Ancora.Gate.Preflight
  alias Ancora.Index
  alias Ancora.Overlap
  alias Ancora.Severity
  alias Ancora.SubjectFiles
  alias Ancora.TagFindings
  alias Ancora.TagScanner
  alias Ancora.Trailer
  alias Ancora.Verifier

  @spec check(Path.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def check(root, opts \\ []) when is_binary(root) and is_list(opts) do
    case Preflight.run(root, opts) do
      {:ok, preflight} -> run_after_preflight(preflight, opts)
      {:env, message} = error -> json_preflight_error(error, message, opts)
    end
  end

  defp run_after_preflight(preflight, opts) do
    with {:ok, ctx} <- RunContext.start(preflight.root, preflight.base) do
      try do
        run(ctx, preflight, opts)
      after
        RunContext.stop(ctx)
      end
    end
  end

  defp json_preflight_error(error, message, opts) do
    if Keyword.get(opts, :json, false) do
      {:ok,
       %{
         findings: [],
         all_findings: [],
         checked: %{subjects: 0, requirements: 0, errors: 0, warnings: 0},
         errors: 0,
         warnings: 0,
         tier: :env,
         fail: true,
         message: message,
         json: true
       }}
    else
      error
    end
  end

  defp run(ctx, preflight, opts) do
    with {:ok, change_set} <- ChangeSet.compute(ctx),
         {:ok, base_root} <- BaseView.materialize(ctx) do
      try do
        assemble(ctx, preflight, change_set, base_root, opts)
      after
        File.rm_rf(base_root)
      end
    else
      {:error, reason} -> raise "gate assembly failed: #{inspect(reason)}"
    end
  end

  defp assemble(ctx, preflight, change_set, base_root, opts) do
    prepare_base_dirs(base_root, preflight.root)
    index_opts = index_opts(opts)
    current = Index.build(preflight.root, index_opts)
    prior = Index.build(base_root, index_opts)
    preflight = %{preflight | config: validate_override_subjects(preflight.config, current)}

    with {:ok, locator, pipeline_findings} <- build_locator(preflight.project, change_set),
         {:ok, head_tags} <- scan_tags(preflight.root, preflight.config.test_paths),
         {:ok, base_tags} <- scan_tags(base_root, preflight.config.test_paths),
         {:ok, head_sets, base_sets} <-
           derive_sets(
             preflight,
             change_set,
             locator,
             head_tags,
             base_tags,
             base_root,
             subject_ids(current)
           ) do
      findings =
        all_findings(
          ctx,
          preflight,
          change_set,
          locator,
          current,
          prior,
          head_tags,
          head_sets,
          base_sets,
          base_root,
          pipeline_findings
        )

      {:ok, report(preflight, change_set, current, head_sets, findings, opts)}
    else
      {:error, reason} -> raise "gate assembly failed: #{inspect(reason)}"
    end
  end

  defp all_findings(
         ctx,
         preflight,
         change_set,
         locator,
         current,
         prior,
         head_tags,
         head_sets,
         base_sets,
         base_root,
         pipeline_findings
       ) do
    subjects = subject_ids(current)

    compare =
      Enum.flat_map(subjects, fn subject_id ->
        head = Map.get(head_sets, subject_id, empty_set(subject_id, :head))
        base = Map.get(base_sets, subject_id, empty_set(subject_id, :base))

        if acknowledged?(subject_id, current, prior, preflight.root, base_root) do
          Compare.compare(subject_id, base, head,
            locator: locator,
            change_set: change_set,
            root: preflight.root
          )
          |> Enum.reject(&(&1.code in ["derived/drift", "derived/growth", "derived/shrink"]))
        else
          Compare.compare(subject_id, base, head,
            locator: locator,
            change_set: change_set,
            root: preflight.root
          )
        end
      end)

    footprints =
      head_sets
      |> SubjectFiles.build(locator)
      |> Map.put(:__lib_paths__, preflight.project.lib_paths)

    tag_ids = Map.keys(head_tags.tag_map)

    (pipeline_findings ++
       preflight.config.findings ++
       current["findings"] ++
       Verifier.verify(current) ++
       Overlap.analyze(current["subjects"]) ++
       TagFindings.findings(
         current,
         head_tags.tag_map,
         head_tags.parse_errors,
         head_tags.dynamics
       ) ++
       AppendOnly.analyze(prior, current) ++
       compare ++
       set_visibility_findings(head_sets) ++
       ChangeAnalysis.findings(change_set, footprints, prior, current, tag_ids))
    |> resolve_findings(preflight, ctx)
  end

  defp build_locator(project, change_set) do
    case ModuleLocator.build(project, change_set) do
      {:ok, locator} ->
        {:ok, locator, []}

      {:error, {:unparseable_source, side, path, reason}} ->
        finding =
          Finding.new(
            code: "derived/unparseable_source",
            file: path,
            message:
              "cannot parse #{path} at #{side} " <>
                "(#{Exception.format_banner(:error, reason)}); fix the source"
          )

        {:ok, %ModuleLocator{}, [finding]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_override_subjects(config, index) do
    known_subjects = MapSet.new(subject_ids(index))

    known_requirements =
      index["subjects"]
      |> Enum.flat_map(fn subject ->
        subject["requirements"]
        |> List.wrap()
        |> Enum.map(&(Map.get(&1, :id) || Map.get(&1, "id")))
        |> Enum.reject(&is_nil/1)
      end)
      |> MapSet.new()

    {valid, unknown} =
      Enum.split_with(config.overrides, fn override ->
        MapSet.member?(known_subjects, override.subject) and
          (is_nil(override.requirement) or
             MapSet.member?(known_requirements, override.requirement))
      end)

    findings =
      Enum.map(unknown, fn override ->
        detail =
          if MapSet.member?(known_subjects, override.subject) do
            "override names unknown requirement #{override.requirement}"
          else
            "override names unknown subject #{override.subject}"
          end

        Finding.new(
          code: "config/invalid_value",
          file: ".spec/config.yml",
          detail: detail
        )
      end)

    %{config | overrides: valid, findings: config.findings ++ findings}
  end

  defp derive_sets(preflight, change_set, locator, head_tags, base_tags, base_root, subjects) do
    membership = %Membership{
      head: ModuleLocator.modules(locator, :head),
      base: ModuleLocator.modules(locator, :base)
    }

    with {:ok, head_indexes} <- def_indexes(locator.head, preflight.root),
         {:ok, base_indexes} <- def_indexes(locator.base, base_root),
         {:ok, head_ctx} <- Derive.context({:ok, membership}, :head, head_indexes),
         {:ok, base_ctx} <- Derive.context({:ok, membership}, :base, base_indexes),
         {:ok, head_sets} <-
           Derive.run(subject_files(head_tags.folded, subjects),
             side: :head,
             context: head_ctx,
             sources: source_map(preflight.root, head_tags.files)
           ),
         {:ok, base_sets} <-
           Derive.run(subject_files(base_tags.folded, subjects),
             side: :base,
             context: base_ctx,
             sources: source_map(base_root, base_tags.files)
           ) do
      _ = change_set
      {:ok, head_sets, base_sets}
    end
  end

  defp scan_tags(root, test_paths) do
    paths = Enum.map(test_paths, &Path.join(root, &1))

    with {:ok, tag_map, parse_errors, dynamics} <- TagScanner.scan(paths) do
      tag_map = normalize_tag_map(tag_map, root)
      folded = TagScanner.fold_to_subjects(tag_map)
      files = tag_map |> Map.values() |> List.flatten() |> Enum.map(& &1.file) |> Enum.uniq()

      {:ok,
       %{
         tag_map: tag_map,
         folded: folded,
         files: files,
         parse_errors: normalize_paths(parse_errors, root),
         dynamics: normalize_paths(dynamics, root)
       }}
    end
  end

  defp normalize_tag_map(tag_map, root) do
    Map.new(tag_map, fn {id, entries} ->
      {id,
       Enum.map(entries, &Map.update!(&1, :file, fn path -> Path.relative_to(path, root) end))}
    end)
  end

  defp normalize_paths(entries, root) do
    Enum.map(entries, fn entry ->
      case entry.file do
        nil -> entry
        path -> %{entry | file: Path.relative_to(path, root)}
      end
    end)
  end

  defp subject_files(folded, subject_ids) do
    Map.new(subject_ids, fn id ->
      files = folded |> Map.get(id, []) |> Enum.map(& &1.file) |> Enum.uniq()
      {id, files}
    end)
  end

  defp source_map(root, files) do
    Map.new(files, fn path -> {path, File.read!(Path.join(root, path))} end)
  end

  defp def_indexes(module_paths, root) do
    module_paths
    |> Enum.group_by(fn {_module, path} -> path end, fn {module, _path} -> module end)
    |> Enum.reduce_while({:ok, %{}}, fn {path, modules}, {:ok, indexes} ->
      case DefIndex.build(File.read!(Path.join(root, path)), path) do
        {:ok, index} ->
          {:cont, {:ok, Enum.reduce(modules, indexes, &Map.put(&2, &1, index))}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp set_visibility_findings(subject_sets) do
    Enum.flat_map(subject_sets, fn {subject_id, set} ->
      unresolved = Map.get(set, :unresolved, [])

      unresolved_findings =
        if unresolved == [] do
          []
        else
          details = Enum.map_join(unresolved, ", ", &unresolved_label/1)
          [Finding.new(code: "derived/unresolved_calls", subject: subject_id, detail: details)]
        end

      unanchored =
        if MapSet.size(Derive.all_bindings(set)) == 0 do
          [Finding.new(code: "derived/unanchored_subject", subject: subject_id)]
        else
          []
        end

      Map.get(set, :findings, []) ++ unresolved_findings ++ unanchored
    end)
  end

  defp unresolved_label(entry) do
    kind = Map.get(entry, :kind, :unqualified)
    file = Map.get(entry, :file, "-")
    line = Map.get(entry, :line, 0)
    "#{kind} at #{file}:#{line}"
  end

  defp acknowledged?(subject_id, current, prior, head_root, base_root) do
    head = subject_source(subject_id, current, head_root)
    base = subject_source(subject_id, prior, base_root)
    Ack.acknowledged?(base, head)
  end

  defp subject_source(subject_id, index, root) do
    case Enum.find(index["subjects"], &(subject_id_of(&1) == subject_id)) do
      nil -> nil
      subject -> File.read!(Path.join(root, subject["file"]))
    end
  end

  defp resolve_findings(findings, preflight, ctx) do
    trailer = Trailer.read(preflight.root, ctx.base)

    Severity.resolve_all(findings,
      config: preflight.config,
      trailer_override: trailer.overrides
    )
  end

  defp report(preflight, change_set, index, subject_sets, findings, opts) do
    {info, non_info} = Enum.split_with(findings, &(&1.severity == :info))
    show_info? = Severity.show_info?(verbose: Keyword.get(opts, :verbose, false))
    visible = if show_info?, do: findings, else: non_info
    errors = Enum.count(findings, &(&1.severity == :error))
    warnings = Enum.count(findings, &(&1.severity == :warning))
    hidden_info = if show_info?, do: 0, else: length(info)

    %{
      findings: visible,
      all_findings: findings,
      checked: %{
        subjects: length(index["subjects"]),
        requirements: index["summary"]["requirements"],
        errors: errors,
        warnings: warnings
      },
      branch: %{
        base: preflight.base,
        changed_files: length(ChangeSet.paths(change_set)),
        findings: length(findings),
        errors: errors,
        warnings: warnings,
        info: hidden_info
      },
      guidance: %{
        impacted_subjects: Map.keys(subject_sets) |> Enum.sort(),
        next: "edit the affected spec or production code"
      },
      errors: errors,
      warnings: warnings,
      tier: :branch,
      fail: errors + warnings > 0,
      json: Keyword.get(opts, :json, false)
    }
  end

  defp prepare_base_dirs(base_root, head_root) do
    File.mkdir_p!(Path.join(base_root, ".spec/specs"))

    if File.dir?(Path.join(head_root, ".spec/decisions")) do
      File.mkdir_p!(Path.join(base_root, ".spec/decisions"))
    end
  end

  defp empty_set(subject_id, side) do
    %{
      subject_id: subject_id,
      side: side,
      bindings: MapSet.new(),
      generated: MapSet.new(),
      dep_generated: MapSet.new(),
      unresolved: [],
      test_files: [],
      findings: []
    }
  end

  defp subject_ids(index) do
    Enum.map(index["subjects"], &subject_id_of/1)
  end

  defp subject_id_of(subject) do
    subject |> Map.get("meta") |> Map.get(:id)
  end

  defp index_opts(opts) do
    case Keyword.get(opts, :spec_dir) do
      nil -> []
      spec_dir -> [spec_dir: spec_dir]
    end
  end
end
