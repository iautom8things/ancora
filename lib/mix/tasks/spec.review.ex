defmodule Mix.Tasks.Spec.Review do
  use Mix.Task

  @requirements ["deps.loadpaths"]
  @shortdoc "Renders a spec-aware review artifact"

  @switches [root: :string, spec_dir: :string, base: :string, output: :string, open: :boolean]

  @impl Mix.Task
  def run(args) do
    Ancora.Output.gated("spec.review", fn ->
      {opts, rest, invalid} =
        OptionParser.parse(args, strict: @switches, aliases: [r: :root, o: :output])

      with :ok <- Ancora.TaskArgs.validate("spec.review", rest, invalid),
           root = Path.expand(opts[:root] || File.cwd!()),
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

  defp open(path) do
    _ = apply(:wx_misc, :launchDefaultBrowser, [String.to_charlist("file://#{path}")])
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end
end
