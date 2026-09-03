defmodule Ancora.Init do
  @moduledoc false

  @templates [
    {"AGENTS.md.eex", "AGENTS.md", :eex},
    {"agents/SKILL.md", "agents/SKILL.md", :copy},
    {"README.md", "README.md", :copy},
    {"config.yml", "config.yml", :copy},
    {"decisions/README.md", "decisions/README.md", :copy},
    {"specs/project.core.spec.md", "specs/project.core.spec.md", :copy}
  ]

  @spec scaffold(Path.t(), keyword()) :: %{directory: Path.t(), files: [map()]}
  def scaffold(root, opts \\ []) when is_binary(root) and is_list(opts) do
    directory = Path.join(root, ".spec")
    force? = Keyword.get(opts, :force, false)

    files =
      Enum.map(@templates, fn {source, destination, mode} ->
        path = Path.join(directory, destination)
        status = install(source, path, mode, force?)
        %{path: path, status: status}
      end)

    %{directory: directory, files: files}
  end

  defp install(source, path, mode, force?) do
    if File.exists?(path) and not force? do
      :kept
    else
      File.mkdir_p!(Path.dirname(path))

      case mode do
        :copy -> File.cp!(template_path(source), path)
        :eex -> File.write!(path, render(source))
      end

      :wrote
    end
  end

  defp render(relative_path) do
    relative_path
    |> template_path()
    |> EEx.eval_file(read_protocol: Ancora.Output.read_protocol())
  end

  defp template_path(relative_path) do
    :ancora
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("spec_init")
    |> Path.join(relative_path)
  end
end
