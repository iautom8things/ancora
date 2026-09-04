defmodule Ancora.Status do
  @moduledoc """
  Builds the source-derived corpus status report.

  A subject is thin when it has fewer than three derived bindings. The
  threshold is a reporting constant and is not configurable.
  """

  alias Ancora.Config
  alias Ancora.Derive
  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.DefIndex
  alias Ancora.Derive.Membership
  alias Ancora.Derive.ModuleLocator
  alias Ancora.Index
  alias Ancora.ProjectInfo
  alias Ancora.TagScanner

  @thin_threshold 3

  @type report :: %{lines: [String.t()], subjects: [map()]}

  @spec build(Path.t(), keyword()) :: {:ok, report()} | {:env, String.t()}
  def build(root, opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)

    with {:ok, spec_dir} <- spec_dir(root, opts),
         {:ok, _authored_dir} <- Index.detect_authored_dir(root, spec_dir),
         :ok <- corpus(root, spec_dir),
         {:ok, index} <- build_index(root, index_opts(opts)),
         subject_ids = Enum.map(index["subjects"], &subject_id/1),
         config = Config.load(root, known_subjects: subject_ids),
         {:ok, project} <- ProjectInfo.load(root, project_opts(config)),
         {:ok, locator} <- ModuleLocator.build(project, %ChangeSet{}),
         {:ok, subject_sets} <- derive_subject_sets(root, config, locator, subject_ids) do
      subjects = subject_rows(index, config, locator, subject_sets)
      {:ok, report(index, subjects)}
    else
      {:env, message} -> {:env, message}
      {:error, reason} -> {:env, "could not derive status: #{inspect(reason)}"}
    end
  end

  defp corpus(root, spec_dir) do
    files =
      Path.wildcard(Path.join([root, spec_dir, "specs", "**", "*.spec.md"])) ++
        Path.wildcard(Path.join([root, spec_dir, "decisions", "**", "*.md"]))

    Enum.reduce_while(files, :ok, fn path, :ok ->
      case File.read(path) do
        {:ok, _source} ->
          {:cont, :ok}

        {:error, reason} ->
          message = "cannot read #{Path.relative_to(path, root)}: #{:file.format_error(reason)}"
          {:halt, {:env, message}}
      end
    end)
  end

  @spec thin_threshold() :: pos_integer()
  def thin_threshold, do: @thin_threshold

  defp derive_subject_sets(root, config, locator, subject_ids) do
    with {:ok, tag_map, _parse_errors, _dynamics} <- scan_tags(root, config.test_paths),
         {:ok, indexes} <- def_indexes(locator.head, root),
         membership = %Membership{
           head: ModuleLocator.modules(locator, :head),
           base: ModuleLocator.modules(locator, :head)
         },
         {:ok, context} <- Derive.context({:ok, membership}, :head, indexes) do
      subject_files = subject_files(tag_map, subject_ids)

      Derive.run(subject_files,
        side: :head,
        context: context,
        sources: fn path -> File.read(Path.join(root, path)) end
      )
    end
  end

  defp scan_tags(root, test_paths) do
    paths = Enum.map(test_paths, &Path.join(root, &1))

    with {:ok, tag_map, parse_errors, dynamics} <- TagScanner.scan(paths),
         :ok <- readable_tag_files(parse_errors, root) do
      relative =
        Map.new(tag_map, fn {id, entries} ->
          {id,
           Enum.map(entries, &Map.update!(&1, :file, fn path -> Path.relative_to(path, root) end))}
        end)

      {:ok, relative, parse_errors, dynamics}
    end
  end

  defp readable_tag_files(parse_errors, root) do
    case Enum.find(parse_errors, &is_atom(&1.reason)) do
      nil -> :ok
      entry -> {:error, {:source_read, Path.relative_to(entry.file, root), entry.reason}}
    end
  end

  defp subject_files(tag_map, subject_ids) do
    folded = TagScanner.fold_to_subjects(tag_map)

    Map.new(subject_ids, fn id ->
      files = folded |> Map.get(id, []) |> Enum.map(& &1.file) |> Enum.uniq()
      {id, files}
    end)
  end

  defp def_indexes(module_paths, root) do
    module_paths
    |> Enum.group_by(fn {_module, path} -> path end, fn {module, _path} -> module end)
    |> Enum.reduce_while({:ok, %{}}, fn {path, modules}, {:ok, indexes} ->
      case File.read(Path.join(root, path)) do
        {:ok, source} ->
          case DefIndex.build(source, path) do
            {:ok, index} ->
              {:cont, {:ok, Enum.reduce(modules, indexes, &Map.put(&2, &1, index))}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, {:source_read, path, reason}}}
      end
    end)
  end

  defp subject_rows(index, config, locator, subject_sets) do
    index["subjects"]
    |> Enum.filter(&is_binary(subject_id(&1)))
    |> Enum.map(fn subject ->
      id = subject_id(subject)
      set = Map.fetch!(subject_sets, id)
      generated = Map.get(set, :generated, MapSet.new())
      dep_generated = Map.get(set, :dep_generated, MapSet.new())

      %{
        id: id,
        spec_file: subject["file"],
        derived: MapSet.size(Derive.all_bindings(set)),
        project_generated: MapSet.difference(generated, dep_generated) |> MapSet.size(),
        dep_generated: MapSet.size(dep_generated),
        tests: Map.get(set, :test_files, []) |> length(),
        unresolved: Map.get(set, :unresolved, []) |> length(),
        acknowledged?: Config.subject_status(config, id) == :acknowledged,
        footprint: footprint(set, locator)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp footprint(set, locator) do
    defining_files =
      set
      |> Map.get(:bindings, MapSet.new())
      |> Enum.flat_map(fn {module, _name, _arity} ->
        case ModuleLocator.path_for(locator, :head, module) do
          {:ok, path} -> [path]
          :error -> []
        end
      end)

    Map.get(set, :test_files, [])
    |> Kernel.++(defining_files)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp report(index, subjects) do
    empty = Enum.count(subjects, &(&1.derived == 0))
    thin = Enum.count(subjects, &(&1.derived < @thin_threshold))

    lines = [
      "Spec Led Status",
      "subjects=#{length(subjects)} decisions=#{length(index["decisions"])} requirements=#{index["summary"]["requirements"]}",
      "derived subjects=#{length(subjects)} empty=#{empty} thin(<#{@thin_threshold})=#{thin}"
    ]

    %{lines: lines ++ Enum.map(subjects, &subject_line/1), subjects: subjects}
  end

  defp subject_line(subject) do
    acknowledged = if subject.acknowledged?, do: " acknowledged", else: ""

    "#{subject.id} derived=#{subject.derived} " <>
      "generated=#{subject.project_generated}+#{subject.dep_generated} " <>
      "tests=#{subject.tests} unresolved=#{subject.unresolved}#{acknowledged}"
  end

  defp subject_id(subject), do: Index.subject_id(subject)

  defp project_opts(%Config{lib_paths: nil}), do: []
  defp project_opts(%Config{lib_paths: paths}), do: [lib_paths: paths]

  defp index_opts(opts) do
    case Keyword.get(opts, :spec_dir) do
      nil -> []
      spec_dir -> [spec_dir: spec_dir]
    end
  end

  defp spec_dir(root, opts) do
    case Keyword.fetch(opts, :spec_dir) do
      {:ok, spec_dir} -> {:ok, spec_dir}
      :error -> Index.detect_spec_dir(root)
    end
  end

  defp build_index(root, opts) do
    case Index.build(root, opts) do
      {:error, message} -> {:env, message}
      index -> {:ok, index}
    end
  end
end
