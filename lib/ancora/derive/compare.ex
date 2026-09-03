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

  Required options are `:locator` and `:change_set`. Source may be supplied as
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

    set_findings(subject_id, base, head) ++
      transition_findings(subject_id, base, head, locator, change_set) ++
      drift_findings(subject_id, base, head, locator, change_set, parsed_sources)
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

  defp set_findings(subject_id, base, head) do
    base = comparable_bindings(base)
    head = comparable_bindings(head)
    growth = MapSet.difference(head, base)
    shrink = MapSet.difference(base, head)

    []
    |> maybe_set_finding("derived/growth", subject_id, growth)
    |> maybe_set_finding("derived/shrink", subject_id, shrink)
    |> Enum.reverse()
  end

  defp comparable_bindings(subject_set) do
    MapSet.difference(
      Derive.all_bindings(subject_set),
      Map.get(subject_set, :dep_generated, MapSet.new())
    )
  end

  defp maybe_set_finding(findings, code, subject_id, set) do
    if MapSet.size(set) == 0 do
      findings
    else
      [Finding.new(code: code, subject: subject_id, detail: binding_list(set)) | findings]
    end
  end

  defp transition_findings(subject_id, base, head, locator, change_set) do
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
        code: "derived/drift",
        subject: subject_id,
        file: defining_file(binding, locator),
        message:
          "#{subject_id}: #{format_binding(binding)} definition moved into or out of " <>
            "macro-generated code; edit the spec for this subject in the same diff"
      )
    end)
  end

  defp drift_findings(subject_id, base, head, locator, change_set, parsed_sources) do
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
            detail = "#{format_binding(binding)} at line #{line}"

            finding =
              Finding.new(code: "derived/drift", subject: subject_id, file: file, detail: detail)

            {[finding | findings], MapSet.put(seen, key)}
          end

        {:finding, finding} ->
          {[finding | findings], seen}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
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
