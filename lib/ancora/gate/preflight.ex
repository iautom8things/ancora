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
         {:ok, project} <- ProjectInfo.load(root, lib_paths: configured_lib_paths(root, config)),
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

      {:error, _reason} ->
        {:env, "#{root} is not a git repository; run ancora inside a git worktree"}
    end
  end

  defp resolve_base(root, base, _default_base) when is_binary(base) and base != "" do
    case Git.run(root, ["rev-parse", "--verify", "#{base}^{commit}"]) do
      {:ok, _oid} -> {:ok, base}
      {:error, _reason} -> {:env, missing_base_message(base)}
    end
  end

  defp resolve_base(root, nil, default_base) do
    case Git.run(root, ["merge-base", "HEAD", default_base]) do
      {:ok, oid} -> {:ok, String.trim(oid)}
      {:error, _reason} -> {:env, missing_base_message(default_base)}
    end
  end

  defp missing_base_message(base) do
    "base #{inspect(base)} cannot be resolved; run git fetch origin main, pass --base <ref>, " <>
      "or set the default_base config key"
  end

  # Config.load/1 is the sole YAML parse in preflight. ProjectInfo receives its
  # already-resolved paths and therefore cannot re-read the config file.
  defp configured_lib_paths(_root, %Config{lib_paths: paths}), do: paths
end
