defmodule Ancora.Gate.Preflight do
  @moduledoc """
  Resolves the target project, configuration, and comparison base before the gate runs.

  Preflight returns environment errors as data. It never turns them into findings.
  """

  alias Ancora.Config
  alias Ancora.Git
  alias Ancora.ProjectInfo

  @type result :: %{
          root: Path.t(),
          base: String.t(),
          config: Config.t(),
          project: ProjectInfo.t()
        }

  @spec run(Path.t(), keyword()) :: {:ok, result()} | {:env, String.t()}
  def run(root, opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)
    config = Config.load(root)

    with :ok <- git_repo(root),
         :ok <- corpus(root),
         {:ok, project} <- ProjectInfo.load(root, project_opts(config)),
         {:ok, base} <- resolve_base(root, Keyword.get(opts, :base), config.default_base) do
      {:ok, %{root: root, base: base, config: config, project: project}}
    end
  end

  defp git_repo(root) do
    case Git.run(root, ["rev-parse", "--is-inside-work-tree"]) do
      {:ok, output} ->
        if String.trim(output) == "true" do
          :ok
        else
          {:env, "#{root} is not a git repository; run ancora inside a git worktree"}
        end

      {:error, :git_executable_not_found} ->
        {:env, "git executable not found; install git and make it available on PATH"}

      {:error, {:git, _args, output, 128}} ->
        {:env,
         git_failure(
           "#{root} is not a git repository; run ancora inside a git worktree",
           128,
           output
         )}

      {:error, {:git, _args, output, status}} ->
        {:env, git_failure("cannot inspect git repository", status, output)}
    end
  end

  defp corpus(root) do
    if File.dir?(Path.join(root, ".spec")) do
      corpus_files_readable(root)
    else
      {:env, "no .spec/ directory in #{root}; run mix spec.init"}
    end
  end

  defp corpus_files_readable(root) do
    files =
      Path.wildcard(Path.join([root, ".spec", "specs", "**", "*.spec.md"])) ++
        Path.wildcard(Path.join([root, ".spec", "decisions", "**", "*.md"]))

    Enum.reduce_while(files, :ok, fn path, :ok ->
      case File.read(path) do
        {:ok, _source} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:env, unreadable_message(root, path, reason)}}
      end
    end)
  end

  defp unreadable_message(root, path, reason) do
    "cannot read #{Path.relative_to(path, root)}: #{:file.format_error(reason)}"
  end

  defp resolve_base(root, base, _default_base) when is_binary(base) and base != "" do
    case Git.run(root, ["rev-parse", "--verify", "#{base}^{commit}"]) do
      {:ok, _oid} -> {:ok, base}
      {:error, reason} -> {:env, base_failure_message(base, reason)}
    end
  end

  defp resolve_base(root, nil, default_base) do
    case Git.run(root, ["merge-base", "HEAD", default_base]) do
      {:ok, oid} -> {:ok, String.trim(oid)}
      {:error, reason} -> {:env, base_failure_message(default_base, reason)}
    end
  end

  defp missing_base_message(base) do
    "base #{inspect(base)} cannot be resolved; run git fetch origin main, pass --base <ref>, " <>
      "or set the default_base config key"
  end

  defp base_failure_message(_base, :git_executable_not_found) do
    "git executable not found; install git and make it available on PATH"
  end

  defp base_failure_message(base, {:git, _args, output, 128}) do
    missing_base_message(base) <> "; git exited 128: " <> String.trim(output)
  end

  defp base_failure_message(base, {:git, _args, output, status}) do
    missing_base_message(base) <>
      "; git failed with status #{status}: " <> String.trim(output)
  end

  defp git_failure(prefix, status, output) do
    detail = String.trim(output)

    if detail == "",
      do: "#{prefix}; git exited #{status}",
      else: "#{prefix}; git exited #{status}: #{detail}"
  end

  # Config.load/1 is the sole YAML parse in preflight. ProjectInfo receives an
  # override only when the config key was present, so literal elixirc_paths
  # remain authoritative otherwise.
  defp project_opts(%Config{lib_paths: nil}), do: []
  defp project_opts(%Config{lib_paths: paths}), do: [lib_paths: paths]
end
