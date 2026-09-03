defmodule Ancora.ProjectInfo do
  @moduledoc """
  Target-project identity read from source, without loading the target project.

  `mix.exs` is parsed as data. The last expression in `project/0` must be a
  keyword list, and only literal `app:` and `elixirc_paths:` values are
  accepted. Dynamic compile paths fall back to `lib`, unless the target's
  `.spec/config.yml` supplies `lib_paths:`.
  """

  alias Ancora.Config

  @enforce_keys [:root, :app, :lib_paths]
  defstruct [:root, :app, :lib_paths]

  @type t :: %__MODULE__{
          root: Path.t(),
          app: atom(),
          lib_paths: [String.t()]
        }

  @type result :: {:ok, t()} | {:env, String.t()}

  @doc """
  Reads project identity from `root/mix.exs`.

  Pass `lib_paths: paths` to supply an already-resolved config override. With
  no option, a top-level `lib_paths:` key in `.spec/config.yml` overrides the
  compile paths from `mix.exs`.
  """
  @spec load(Path.t(), keyword()) :: result()
  def load(root, opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)
    mix_file = Path.join(root, "mix.exs")

    with {:ok, source} <- read_mix_file(mix_file),
         {:ok, ast} <- parse_mix_file(source, mix_file),
         {:ok, project} <- project_options(ast),
         :ok <- reject_umbrella(project),
         {:ok, app} <- literal_app(project),
         {:ok, lib_paths} <- lib_paths(root, project, opts) do
      {:ok, %__MODULE__{root: root, app: app, lib_paths: lib_paths}}
    end
  end

  defp read_mix_file(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:env, "could not read target mix.exs: #{inspect(reason)}"}
    end
  end

  defp parse_mix_file(source, path) do
    case Code.string_to_quoted(source, file: path, emit_warnings: false) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:env, "could not parse target mix.exs: #{inspect(reason)}"}
    end
  end

  defp project_options(ast) do
    {_ast, options} =
      Macro.prewalk(ast, nil, fn
        {:def, _, [{:project, _, args}, body]} = node, nil when args in [nil, []] ->
          {node, literal_project_body(body)}

        node, acc ->
          {node, acc}
      end)

    case options do
      options when is_list(options) -> {:ok, options}
      _ -> {:env, "target mix.exs project/0 must return a keyword list"}
    end
  end

  defp literal_project_body(body) when is_list(body) do
    case Keyword.fetch(body, :do) do
      {:ok, return_value} -> literal_return_value(return_value)
      _ -> nil
    end
  end

  defp literal_project_body(_body), do: nil

  defp literal_return_value({:__block__, _meta, expressions}) when is_list(expressions) do
    expressions
    |> List.last()
    |> literal_return_value()
  end

  defp literal_return_value(options) when is_list(options), do: options
  defp literal_return_value(_return_value), do: nil

  defp reject_umbrella(project) do
    if Keyword.has_key?(project, :apps_path) do
      {:env,
       "umbrella roots are not supported; run ancora inside a child app if you must, unsupported"}
    else
      :ok
    end
  end

  defp literal_app(project) do
    case Keyword.fetch(project, :app) do
      {:ok, app} when is_atom(app) and not is_nil(app) ->
        {:ok, app}

      _ ->
        {:env,
         "target mix.exs must define app: as a literal atom; dynamic app values are unsupported"}
    end
  end

  defp lib_paths(root, project, opts) do
    case Keyword.fetch(opts, :lib_paths) do
      {:ok, paths} -> validate_lib_paths(paths)
      :error -> project_lib_paths(root, project)
    end
  end

  defp project_lib_paths(root, project) do
    case configured_lib_paths(root) do
      nil -> literal_elixirc_paths(project)
      paths -> validate_lib_paths(paths)
    end
  end

  defp literal_elixirc_paths(project) do
    case Keyword.get(project, :elixirc_paths, ["lib"]) do
      paths when is_list(paths) ->
        if Enum.all?(paths, &is_binary/1), do: validate_lib_paths(paths), else: {:ok, ["lib"]}

      _dynamic ->
        {:ok, ["lib"]}
    end
  end

  defp validate_lib_paths(paths)
       when is_list(paths) and paths != [] do
    if Enum.all?(paths, &(is_binary(&1) and &1 != "")) do
      {:ok, Enum.map(paths, &String.trim_trailing(&1, "/"))}
    else
      {:env, "lib_paths must be a non-empty list of paths"}
    end
  end

  defp validate_lib_paths(_paths), do: {:env, "lib_paths must be a non-empty list of paths"}

  defp configured_lib_paths(root) do
    path = Path.join([root, ".spec", "config.yml"])

    with {:ok, source} <- File.read(path),
         {:ok, config} when is_map(config) <- YamlElixir.read_from_string(source),
         true <- Map.has_key?(config, "lib_paths") do
      Config.load(root).lib_paths
    else
      _ -> nil
    end
  end
end
