defmodule Mix.Tasks.Spec.Review do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Renders a spec-aware review artifact"
  @moduledoc """
  Renders an HTML review of the current change set.

  A cold checkout may print dependency compilation lines before ancora output.

  ## Options

    * `--base REF` selects the git base. Defaults to configured `default_base`.
    * `--output PATH`, `-o PATH` selects the artifact path. Defaults to `_build/spec_review.html`.
    * `--open` opens the artifact in the system browser. Defaults to false.
    * `--root DIR`, `-r DIR` selects the target project. Defaults to the current directory.
    * `--spec-dir DIR` selects the ancora workspace directory. Defaults to `.spec`.
  """

  @switches [root: :string, spec_dir: :string, base: :string, output: :string, open: :boolean]

  @impl Mix.Task
  def run(args) do
    Ancora.Output.gated("spec.review", fn ->
      {opts, rest, invalid} =
        OptionParser.parse(args, strict: @switches, aliases: [r: :root, o: :output])

      with :ok <- Ancora.TaskArgs.validate("spec.review", rest, invalid),
           root = Path.expand(opts[:root] || File.cwd!()),
           :ok <- validate_spec_dir(root, opts),
           {:ok, view} <- Ancora.Review.build(root, opts) do
        html = view |> Ancora.Review.Html.render() |> IO.iodata_to_binary()
        output = output_path(opts[:output], root)
        File.mkdir_p!(Path.dirname(output))
        File.write!(output, html)
        if opts[:open], do: open(output)

        relative = Path.relative_to(output, root)

        {:ok,
         %{
           lines: [
             "spec.review wrote #{relative} (#{byte_size(html)} bytes)",
             "  base=#{view.meta.base_ref} head=#{view.meta.head_ref} affected_subjects=#{view.meta.affected_subjects} findings=#{view.meta.findings}"
           ]
         }}
      else
        {:error, message} -> {:usage, message}
        {:env, message} -> {:env, message}
      end
    end)
  end

  defp output_path(nil, root), do: Path.join([root, "_build", "spec_review.html"])

  defp output_path(path, root),
    do: if(Path.type(path) == :absolute, do: path, else: Path.expand(path, root))

  defp validate_spec_dir(root, opts) do
    with {:ok, spec_dir} <- spec_dir(root, opts),
         {:ok, _authored_dir} <- Ancora.Index.detect_authored_dir(root, spec_dir) do
      :ok
    else
      {:error, message} -> {:env, message}
    end
  end

  defp spec_dir(root, opts) do
    case Keyword.fetch(opts, :spec_dir) do
      {:ok, spec_dir} -> {:ok, spec_dir}
      :error -> Ancora.Index.detect_spec_dir(root)
    end
  end

  defp open(path) do
    _ = apply(:wx_misc, :launchDefaultBrowser, [String.to_charlist("file://#{path}")])
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end
end
