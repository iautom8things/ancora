defmodule Ancora.TmpGitRepo do
  @moduledoc false

  def create! do
    root = Path.join(System.tmp_dir!(), "ancora-git-#{Ancora.TempName.cross_vm_suffix()}")

    File.rm_rf!(root)
    File.mkdir_p!(root)
    {:ok, _} = Ancora.Git.run(root, ["init", "-b", "main"])
    {:ok, _} = Ancora.Git.run(root, ["config", "user.name", "Ancora Test"])
    {:ok, _} = Ancora.Git.run(root, ["config", "user.email", "ancora@example.com"])
    {:ok, _} = Ancora.Git.run(root, ["config", "commit.gpgsign", "false"])
    {:ok, _} = Ancora.Git.run(root, ["config", "core.hooksPath", "/dev/null"])
    root
  end

  def write!(root, files) do
    Enum.each(files, fn {path, content} ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end)

    root
  end

  def commit!(root, message) do
    {:ok, _} = Ancora.Git.run(root, ["add", "-A"])
    {:ok, _} = Ancora.Git.run(root, ["commit", "--no-verify", "-m", message])
    root
  end

  def cleanup!(root) do
    # Port.close returns before the OS git process fully exits; deleting
    # `.git` under it prints `fatal: not a git repository` on stderr.
    Process.sleep(30)
    File.rm_rf(root)
  end

  def git!(root, args) do
    case Ancora.Git.run(root, args) do
      {:ok, output} ->
        output

      {:error, {:git, ^args, output, status}} ->
        raise "git #{Enum.join(args, " ")} failed (#{status}): #{String.trim(output)}"
    end
  end
end
