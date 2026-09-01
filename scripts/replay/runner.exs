Code.require_file("case.exs", __DIR__)
Code.require_file("json.exs", __DIR__)
Code.require_file("result.exs", __DIR__)

defmodule AncoraReplay.Runner do
  @moduledoc false

  alias AncoraReplay.Case
  alias AncoraReplay.Json
  alias AncoraReplay.Result

  @minimal_config """
  test_paths:
    - test
  lib_paths:
    - lib
  severities:
    change/missing_decision: off
    change/uncovered_file: off
    derived/unanchored_subject: off
  """

  @spec run(Path.t(), Path.t(), Case.t()) :: Result.evaluation()
  def run(ancora_root, consumer_repo, %Case{} = replay_case) do
    with :ok <- git_object_exists(consumer_repo, replay_case.sha),
         {:ok, worktree_parent} <- fresh_dir("ancora-replay"),
         worktree = Path.join(worktree_parent, "consumer"),
         :ok <- add_worktree(consumer_repo, worktree, replay_case.sha) do
      try do
        with :ok <- install_config(worktree),
             {:ok, stdout} <- run_gate(ancora_root, worktree, replay_case.sha <> "^"),
             {:ok, report} <- Json.parse(stdout) do
          Result.evaluate(replay_case, report)
        else
          {:error, message} -> {:error, "#{replay_case.name}: #{message}"}
        end
      after
        remove_worktree(consumer_repo, worktree)
        File.rm_rf(worktree_parent)
      end
    else
      {:error, message} -> {:error, "#{replay_case.name}: #{message}"}
    end
  rescue
    exception -> {:error, "#{replay_case.name}: #{Exception.message(exception)}"}
  end

  defp git_object_exists(repo, sha) do
    case System.cmd("git", ["-C", repo, "cat-file", "-e", "#{sha}^{commit}"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, status} ->
        {:error, "git cannot resolve #{sha} (#{status}): #{String.trim(output)}"}
    end
  end

  defp fresh_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, "cannot create #{path}: #{inspect(reason)}"}
    end
  end

  defp add_worktree(repo, worktree, sha) do
    case System.cmd("git", ["-C", repo, "worktree", "add", "--detach", worktree, sha],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "git worktree add failed (#{status}): #{String.trim(output)}"}
    end
  end

  defp install_config(worktree) do
    config = Path.join(worktree, ".spec/config.yml")
    File.mkdir_p!(Path.dirname(config))

    temp = config <> ".ancora-replay-#{System.unique_integer([:positive, :monotonic])}"

    with {:ok, file} <- File.open(temp, [:write, :exclusive]),
         :ok <- IO.binwrite(file, @minimal_config),
         :ok <- File.close(file),
         true <- File.regular?(temp) and File.read!(temp) != "",
         :ok <- File.rename(temp, config),
         true <- File.read!(config) == @minimal_config do
      :ok
    else
      false -> {:error, "minimal config postcondition failed"}
      {:error, reason} -> {:error, "cannot install minimal config: #{inspect(reason)}"}
    end
  end

  defp run_gate(ancora_root, worktree, base) do
    {stdout, status} =
      System.cmd(
        "mix",
        ["spec.check", "--root", worktree, "--base", base, "--json"],
        cd: ancora_root,
        env: [{"MIX_ENV", "dev"}]
      )

    if status in [0, 1] do
      {:ok, stdout}
    else
      {:error, "spec.check exited #{status}"}
    end
  end

  defp remove_worktree(repo, worktree) do
    _ =
      System.cmd("git", ["-C", repo, "worktree", "remove", "--force", worktree],
        stderr_to_stdout: true
      )

    :ok
  end
end
