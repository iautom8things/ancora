defmodule Ancora.Derive.Compare do
  @moduledoc """
  Computes growth, shrink, and diff-scoped source drift for one subject.
  """

  alias Ancora.Canonical
  alias Ancora.Derive
  alias Ancora.Derive.ChangeSet
  alias Ancora.Derive.Extract
  alias Ancora.Derive.ModuleLocator
  alias Ancora.Finding

  @doc """
  Compares a subject's base and HEAD derived sets.

  Required options are `:locator` and `:change_set`. The optional `:surface`
  is the subject's authored file list; when absent, all drift stays primary.
  Source may be supplied as
  `sources: %{base: %{path => source}, head: %{path => source}}` or as a
  two-argument `source_reader`. With neither, `:root` supplies HEAD reads and
  the change set supplies changed base blobs. Gate callers may pass one
  `:parsed_sources` map prepared across every subject in the run.
  """
  @spec compare(String.t(), Derive.subject_set(), Derive.subject_set(), keyword()) ::
          [Finding.t()]
  def compare(subject_id, base, head, opts)
      when is_binary(subject_id) and is_map(base) and is_map(head) and is_list(opts) do
    locator = Keyword.fetch!(opts, :locator)
    change_set = Keyword.fetch!(opts, :change_set)

    parsed_sources =
      Keyword.get_lazy(opts, :parsed_sources, fn ->
        prepare_sources([{base, head}], locator, change_set, opts)
      end)

    set_findings(subject_id, base, head, locator, opts) ++
      transition_findings(subject_id, base, head, locator, change_set, opts) ++
      drift_findings(subject_id, base, head, locator, change_set, parsed_sources, opts)
  end

  @doc "Parses each changed defining file once per side for a set of subject pairs."
  @spec prepare_sources(
          [{Derive.subject_set(), Derive.subject_set()}],
          ModuleLocator.t(),
          ChangeSet.t(),
          keyword()
        ) :: %{base: map(), head: map()}
  def prepare_sources(subject_pairs, locator, change_set, opts)
      when is_list(subject_pairs) and is_list(opts) do
    bindings =
      subject_pairs
      |> Enum.flat_map(fn {base, head} ->
        base
        |> Map.get(:bindings, MapSet.new())
        |> MapSet.intersection(Map.get(head, :bindings, MapSet.new()))
      end)
      |> MapSet.new()

    Map.new([:base, :head], fn side ->
      paths =
        bindings
        |> Enum.flat_map(fn {module, _name, _arity} ->
          case ModuleLocator.path_for(locator, side, module) do
            {:ok, path} -> [path]
            :error -> []
          end
        end)
        |> Enum.filter(&ChangeSet.changed_path?(change_set, &1))
        |> Enum.uniq()

      parsed =
        Map.new(paths, fn path ->
          result =
            with {:ok, source} <- read_source(side, path, change_set, opts) do
              Extract.parse(source, path)
            end

          {path, result}
        end)

      {side, parsed}
    end)
  end

  defp set_findings(subject_id, base, head, locator, opts) do
    growth = MapSet.difference(comparable_bindings(head), comparable_bindings(base))
    shrink = MapSet.difference(comparable_bindings(base), comparable_bindings(head))

    uncertain =
      MapSet.new(
        Map.get(head, :unresolved, []),
        &{Map.get(&1, :test_file, &1.file), Map.get(&1, :carrier)}
      )

    shrink =
      Enum.reject(shrink, fn binding ->
        origins = Enum.filter(Map.get(base, :provenance, []), &(&1.binding == binding))

        origins != [] and
          Enum.all?(origins, &MapSet.member?(uncertain, {&1.test_file, &1.carrier}))
      end)
      |> MapSet.new()

    {growth, growth_transitive} = Enum.split_with(growth, &primary?(&1, locator, opts))
    {shrink, shrink_transitive} = Enum.split_with(shrink, &primary?(&1, locator, opts))

    []
    |> maybe_set_finding("derived/growth", subject_id, growth)
    |> maybe_set_finding("derived/shrink", subject_id, shrink)
    |> maybe_set_finding("derived/growth_transitive", subject_id, growth_transitive)
    |> maybe_set_finding("derived/shrink_transitive", subject_id, shrink_transitive)
    |> Enum.reverse()
  end

  defp comparable_bindings(subject_set) do
    MapSet.difference(
      Derive.all_bindings(subject_set),
      Map.get(subject_set, :dep_generated, MapSet.new())
    )
  end

  defp maybe_set_finding(findings, code, subject_id, set) do
    if Enum.empty?(set) do
      findings
    else
      [Finding.new(code: code, subject: subject_id, detail: binding_list(set)) | findings]
    end
  end

  defp transition_findings(subject_id, base, head, locator, change_set, opts) do
    shared = MapSet.intersection(Derive.all_bindings(base), Derive.all_bindings(head))
    base_textual = Map.get(base, :bindings, MapSet.new())
    head_textual = Map.get(head, :bindings, MapSet.new())

    shared
    |> Enum.filter(fn binding ->
      MapSet.member?(base_textual, binding) != MapSet.member?(head_textual, binding)
    end)
    |> Enum.filter(&changed_definition?(&1, locator, change_set))
    |> Enum.uniq_by(fn {module, name, _arity} -> {module, name} end)
    |> Enum.map(fn binding ->
      Finding.new(
        code: binding_code("derived/drift", binding, locator, opts),
        subject: subject_id,
        file: defining_file(binding, locator),
        message:
          "#{subject_id}: #{format_binding(binding)} definition moved into or out of " <>
            "macro-generated code; edit the spec for this subject in the same diff"
      )
    end)
  end

  defp drift_findings(subject_id, base, head, locator, change_set, parsed_sources, opts) do
    base_textual = Map.get(base, :bindings, MapSet.new())
    head_textual = Map.get(head, :bindings, MapSet.new())

    base_textual
    |> MapSet.intersection(head_textual)
    |> Enum.filter(&changed_definition?(&1, locator, change_set))
    |> Enum.sort_by(&format_binding/1)
    |> Enum.reduce({[], MapSet.new()}, fn binding, {findings, seen} ->
      case compare_binding(binding, locator, parsed_sources) do
        {:equal, _key} ->
          {findings, seen}

        {:drift, key, file, line} ->
          if MapSet.member?(seen, key) do
            {findings, seen}
          else
            detail =
              "#{format_binding(binding)} at line #{line}" <> provenance_detail(head, binding)

            finding =
              Finding.new(
                code: binding_code("derived/drift", binding, locator, opts),
                subject: subject_id,
                file: file,
                detail: detail
              )

            {[finding | findings], MapSet.put(seen, key)}
          end

        {:finding, finding} ->
          {[finding | findings], seen}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp provenance_detail(set, binding) do
    origins =
      Map.get(set, :provenance, [])
      |> Enum.filter(&(&1.binding == binding))
      |> Enum.uniq_by(&{&1.test_file, &1.carrier})

    case Enum.take(origins, 3) do
      [] ->
        ""

      entries ->
        "; observed by " <>
          Enum.map_join(entries, ", ", fn origin ->
            chain = Enum.map_join(origin.chain, " -> ", &"#{&1.file}:#{&1.line}")
            "#{chain} -> #{origin.file}:#{origin.line}"
          end)
    end
  end

  defp compare_binding({module, name, _arity} = binding, locator, parsed_sources) do
    with {:ok, base_path} <- ModuleLocator.path_for(locator, :base, module),
         {:ok, head_path} <- ModuleLocator.path_for(locator, :head, module),
         {:ok, base_clauses} <- clauses_for(parsed_sources, :base, base_path, binding),
         {:ok, head_clauses} <- clauses_for(parsed_sources, :head, head_path, binding) do
      base_normalized = Canonical.normalize(base_clauses)
      head_normalized = Canonical.normalize(head_clauses)
      key = {module, name, base_normalized, head_normalized}

      if base_normalized == head_normalized do
        {:equal, key}
      else
        {:drift, key, head_path, first_line(head_clauses)}
      end
    else
      {:error, {:unparseable_source, path, reason}} ->
        {:finding, unparseable_finding(path, reason)}

      {:error, reason} ->
        {:finding, unparseable_finding(defining_file(binding, locator), reason)}

      :error ->
        {:equal, {module, name, :missing}}
    end
  end

  defp changed_definition?({module, _name, _arity}, locator, change_set) do
    Enum.any?([:base, :head], fn side ->
      case ModuleLocator.path_for(locator, side, module) do
        {:ok, path} -> ChangeSet.changed_path?(change_set, path)
        :error -> false
      end
    end)
  end

  defp clauses_for(parsed_sources, side, path, binding) do
    case get_in(parsed_sources, [side, path]) do
      {:ok, ast} -> {:ok, Extract.clauses(ast, binding)}
      {:error, _reason} = error -> error
      nil -> :error
    end
  end

  defp defining_file({module, _name, _arity}, locator) do
    case ModuleLocator.path_for(locator, :head, module) do
      {:ok, path} ->
        path

      :error ->
        case ModuleLocator.path_for(locator, :base, module) do
          {:ok, path} -> path
          :error -> nil
        end
    end
  end

  defp binding_code(code, binding, locator, opts),
    do: if(primary?(binding, locator, opts), do: code, else: code <> "_transitive")

  defp primary?({module, _, _}, locator, opts) do
    case Keyword.get(opts, :surface) do
      surface when is_list(surface) and surface != [] ->
        base_surface = Keyword.get(opts, :base_surface, [])
        owned = surface ++ if(is_list(base_surface), do: base_surface, else: [])
        paths = Enum.map([:base, :head], &ModuleLocator.path_for(locator, &1, module))
        known = for {:ok, path} <- paths, do: path
        known == [] or Enum.any?(known, &(&1 in owned))

      _ ->
        true
    end
  end

  defp read_source(side, path, change_set, opts) do
    case Keyword.fetch(opts, :source_reader) do
      {:ok, reader} when is_function(reader, 2) -> normalize_read(reader.(side, path), path)
      :error -> read_configured_source(side, path, change_set, opts)
    end
  end

  defp read_configured_source(side, path, change_set, opts) do
    case Keyword.get(opts, :sources) do
      sources when is_map(sources) ->
        sources |> Map.get(side, %{}) |> Map.fetch(path) |> normalize_read(path)

      nil ->
        read_project_source(side, path, change_set, Keyword.fetch!(opts, :root))
    end
  end

  defp read_project_source(:head, path, _change_set, root), do: File.read(Path.join(root, path))

  defp read_project_source(:base, path, change_set, root) do
    case Map.get(change_set.prefetched, path, :unchanged) do
      {:ok, source} -> {:ok, source}
      :missing -> {:error, {:missing_source, :base, path}}
      :unchanged -> File.read(Path.join(root, path))
    end
  end

  defp normalize_read({:ok, source}, _path) when is_binary(source), do: {:ok, source}
  defp normalize_read(source, _path) when is_binary(source), do: {:ok, source}
  defp normalize_read(:error, path), do: {:error, {:missing_source, path}}
  defp normalize_read({:error, reason}, _path), do: {:error, reason}
  defp normalize_read(other, path), do: {:error, {:invalid_source, path, other}}

  defp unparseable_finding(path, reason) do
    Finding.new(
      code: "derived/unparseable_source",
      file: path,
      message:
        "cannot parse #{path} while comparing drift " <>
          "(#{Exception.format_banner(:error, reason)}); fix the source"
    )
  end

  defp first_line([{_kind, metadata, _arguments} | _]), do: Keyword.get(metadata, :line, 0)
  defp first_line(_clauses), do: 0

  defp binding_list(bindings) do
    rendered = bindings |> Enum.map(&format_binding/1) |> Enum.sort()
    {shown, remaining} = Enum.split(rendered, 10)
    suffix = if remaining == [], do: "", else: ", +#{length(remaining)} more"
    Enum.join(shown, ", ") <> suffix
  end

  defp format_binding({module, name, arity}) do
    module = module |> to_string() |> String.trim_leading("Elixir.")
    "#{module}.#{name}/#{arity}"
  end
end
