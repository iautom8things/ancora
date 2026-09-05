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

  def shallow_clone!(source, opts \\ []) do
    root = Path.join(System.tmp_dir!(), "ancora-shallow-#{Ancora.TempName.cross_vm_suffix()}")
    depth = Keyword.get(opts, :depth, 1)
    branch = Keyword.get(opts, :branch, "main")

    {:ok, _} =
      Ancora.Git.run(System.tmp_dir!(), [
        "clone",
        "--depth=#{depth}",
        "--branch=#{branch}",
        "file://#{source}",
        root
      ])

    root
  end

  def cleanup!(root) do
    # Port.close returns before the OS git process fully exits; deleting
    # `.git` under it prints `fatal: not a git repository` on stderr.
    Process.sleep(30)
    File.rm_rf(root)
  end

  def commit_tree_path!(root, components, opts \\ []) do
    input = Path.join(root, ".git/tree-input")
    File.write!(input, "hostile tree payload\n")
    blob = root |> git!(["hash-object", "-w", input]) |> String.trim()

    tree =
      components
      |> Enum.reverse()
      |> Enum.reduce({"100644 blob", blob}, fn name, {kind, oid} ->
        entry = "#{kind} #{oid}\t#{name}\0"

        entry =
          if name == hd(components) and Keyword.get(opts, :leading_blob, false) do
            "100644 blob #{blob}\t0-safe.txt\0" <> entry
          else
            entry
          end

        File.write!(input, entry)

        {output, 0} =
          System.cmd("sh", ["-c", "git mktree -z < \"$1\"", "mktree", input], cd: root)

        {"040000 tree", String.trim(output)}
      end)
      |> elem(1)

    root |> git!(["commit-tree", tree, "-m", "tree path fixture"]) |> String.trim()
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
