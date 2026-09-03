defmodule Ancora.Init do
  @moduledoc false

  @templates [
    {"AGENTS.md.eex", "AGENTS.md"},
    {"agents/SKILL.md.eex", "agents/SKILL.md"},
    {"README.md.eex", "README.md"},
    {"config.yml.eex", "config.yml"},
    {"decisions/README.md.eex", "decisions/README.md"},
    {"specs/project.core.spec.md.eex", "specs/project.core.spec.md"}
  ]

  @spec scaffold(Path.t(), keyword()) :: %{directory: Path.t(), files: [map()]}
  def scaffold(root, opts \\ []) when is_binary(root) and is_list(opts) do
    directory = Path.join(root, ".spec")
    force? = Keyword.get(opts, :force, false)

    files =
      Enum.map(@templates, fn {source, destination} ->
        path = Path.join(directory, destination)
        status = write(path, render(source), force?)
        %{path: path, status: status}
      end)

    %{directory: directory, files: files}
  end

  defp write(path, content, force?) do
    if File.exists?(path) and not force? do
      :kept
    else
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
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
