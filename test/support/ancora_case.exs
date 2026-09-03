unless Code.ensure_loaded?(Ancora.TestCase) do
  defmodule Ancora.TestCase do
    @moduledoc false
    use ExUnit.CaseTemplate

    using options do
      quote do
        use ExUnit.Case, async: Keyword.get(unquote(options), :async, true)
        import Ancora.TestCase
        import ExUnit.CaptureIO

        setup_all do
          build_path =
            Path.join(
              Path.dirname(Mix.Project.build_path()),
              "ancora-mix-#{Ancora.TempName.cross_vm_suffix()}"
            )

          File.rm_rf!(build_path)
          on_exit(fn -> File.rm_rf!(build_path) end)
          {:ok, ancora_mix_build_path: build_path}
        end

        setup %{ancora_mix_build_path: build_path} do
          Process.put(:ancora_mix_build_path, build_path)
          :ok
        end
      end
    end

    setup do
      root = Path.join(System.tmp_dir!(), "ancora-#{Ancora.TempName.cross_vm_suffix()}")

      File.rm_rf!(root)
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

    def write_test_file(root, relative, content) do
      path = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      path
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

    def run_mix_subprocess(args, opts \\ []) do
      real_mix = System.find_executable("mix")
      suffix = Ancora.TempName.cross_vm_suffix()

      wrapper_dir = Path.join(System.tmp_dir!(), "ancora-mix-#{suffix}")

      stderr_path = Path.join(wrapper_dir, "stderr")
      build_path = Process.get(:ancora_mix_build_path)
      wrapper = Path.join(wrapper_dir, "mix")
      File.rm_rf!(wrapper_dir)
      File.mkdir_p!(wrapper_dir)
      seed_build_path!(build_path)
      File.write!(wrapper, "#!/bin/sh\nexec #{real_mix} \"$@\" 2>\"$ANCORA_STDERR_FILE\"\n")
      File.chmod!(wrapper, 0o755)

      {stdout, status} =
        System.cmd(wrapper, args,
          cd: Keyword.get(opts, :cd, File.cwd!()),
          env: [
            {"ANCORA_STDERR_FILE", stderr_path},
            {"MIX_BUILD_PATH", build_path},
            {"MIX_ENV", Atom.to_string(Mix.env())},
            {"MIX_QUIET", "1"}
          ]
        )

      stderr = File.read!(stderr_path)
      File.rm_rf!(wrapper_dir)
      %{stdout: stdout, stderr: stderr, status: status}
    end

    defp seed_build_path!(build_path) do
      unless File.dir?(build_path) do
        source = Mix.Project.build_path()

        case :os.type() do
          {:unix, :darwin} -> clone_build_path!(source, build_path)
          _other -> File.cp_r!(source, build_path)
        end
      end
    end

    defp clone_build_path!(source, build_path) do
      case System.cmd("/bin/cp", ["-cR", source, build_path], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {_output, _status} ->
          File.rm_rf!(build_path)
          File.cp_r!(source, build_path)
      end
    end

    def output_lines(output), do: String.split(output, "\n", trim: true)
  end
end
