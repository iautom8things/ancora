unless Code.ensure_loaded?(Ancora.TestCase) do
  defmodule Ancora.TestCase do
    @moduledoc false
    use ExUnit.CaseTemplate

    using do
      quote do
        use ExUnit.Case, async: true
        import Ancora.TestCase
        import ExUnit.CaptureIO
      end
    end

    setup do
      root =
        Path.join(System.tmp_dir!(), "ancora-#{System.unique_integer([:positive])}")

      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf(root) end)
      {:ok, root: root}
    end

    def write_config(root, contents) do
      path = Path.join([root, ".spec", "config.yml"])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      path
    end

    def write_files(root, files) do
      Enum.each(files, fn {path, content} ->
        full = Path.join(root, path)
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, content)
      end)
    end

    def write_spec(root, name, content) do
      relative = ".spec/specs/#{name}.spec.md"
      write_files(root, %{relative => content})
      Path.join(root, relative)
    end

    def write_decision(root, name, content) do
      relative = ".spec/decisions/#{name}.md"
      write_files(root, %{relative => content})
      Path.join(root, relative)
    end

    def findings_codes(findings) when is_list(findings) do
      Enum.map(findings, & &1.code)
    end

    def init_git_repo(root) do
      git!(root, ["init", "-b", "main"])
      git!(root, ["config", "user.name", "Ancora Test"])
      git!(root, ["config", "user.email", "ancora@example.com"])
    end

    def commit_all(root, message) do
      git!(root, ["add", "."])
      git!(root, ["commit", "-m", message])
    end

    def git!(root, args) do
      env =
        Enum.to_list(System.get_env()) ++
          [
            {"GIT_CONFIG_GLOBAL", "/dev/null"},
            {"GIT_CONFIG_NOSYSTEM", "1"},
            {"GIT_AUTHOR_NAME", "Ancora Test"},
            {"GIT_AUTHOR_EMAIL", "ancora@example.com"},
            {"GIT_COMMITTER_NAME", "Ancora Test"},
            {"GIT_COMMITTER_EMAIL", "ancora@example.com"}
          ]

      {output, status} =
        System.cmd(
          "git",
          ["-C", root, "-c", "commit.gpgsign=false" | args],
          env: env,
          stderr_to_stdout: true
        )

      if status != 0 do
        raise "git #{Enum.join(args, " ")} failed: #{String.trim(output)}"
      end

      output
    end
  end
end
