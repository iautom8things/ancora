defmodule Ancora.Markdown do
  @moduledoc """
  Renders spec and decision prose from Earmark's AST without trusting raw HTML.
  """

  @safe_tags MapSet.new(
               ~w(a blockquote br code del div em h1 h2 h3 h4 h5 h6 hr li ol p pre strong table tbody td th thead tr ul)
             )

  @doc "Render markdown as HTML, degrading to escaped source when parsing or rendering fails."
  @spec render(String.t(), keyword()) :: String.t()
  def render(source, opts \\ []) when is_binary(source) do
    with {:ok, ast, _messages} <- EarmarkParser.as_ast(source, gfm: true) do
      renderer = Keyword.get(opts, :renderer, &render_nodes/1)
      renderer.(ast) |> IO.iodata_to_binary()
    else
      _ -> fallback(source)
    end
  rescue
    _exception -> fallback(source)
  catch
    _kind, _reason -> fallback(source)
  end

  @doc false
  @spec render_nodes(list()) :: iodata()
  def render_nodes(nodes) when is_list(nodes), do: Enum.map(nodes, &render_node/1)

  defp render_node(text) when is_binary(text), do: render_text(text)

  defp render_node({tag, _attrs, children, _meta}) when tag in ["html_inline", "html_block"] do
    children |> raw_text() |> escape()
  end

  defp render_node({tag, attrs, children, _meta}) when is_binary(tag) do
    if MapSet.member?(@safe_tags, tag) do
      ["<", tag, render_attrs(tag, attrs), ">", render_children(children), "</", tag, ">"]
    else
      children |> raw_text() |> escape()
    end
  end

  defp render_node(other), do: other |> inspect() |> escape()

  defp render_children(children) when is_list(children), do: render_nodes(children)
  defp render_children(children) when is_binary(children), do: render_text(children)
  defp render_children(_children), do: ""

  defp render_attrs("a", attrs) when is_list(attrs) do
    case Enum.find(attrs, fn {name, _value} -> name == "href" end) do
      {"href", href} when is_binary(href) -> [" href=\"", safe_href(href), "\""]
      _ -> ""
    end
  end

  defp render_attrs(_tag, _attrs), do: ""

  defp safe_href("#" <> _rest = href), do: escape(href)
  defp safe_href("http://" <> _rest = href), do: escape(href)
  defp safe_href("https://" <> _rest = href), do: escape(href)
  defp safe_href(_href), do: "#"

  defp render_text(text) do
    ~r/\[\[([a-zA-Z0-9_.-]+)\]\]/
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/^\[\[([a-zA-Z0-9_.-]+)\]\]$/, part, capture: :all_but_first) do
        [id] -> ["<a class=\"wikilink\" href=\"#", escape(id), "\">", escape(id), "</a>"]
        _ -> escape(part)
      end
    end)
  end

  defp raw_text(children) when is_binary(children), do: children
  defp raw_text(children) when is_list(children), do: Enum.map_join(children, &raw_text/1)
  defp raw_text({_tag, _attrs, children, _meta}), do: raw_text(children)
  defp raw_text(other), do: to_string(other)

  defp fallback(source), do: "<pre class=\"markdown-fallback\">#{escape(source)}</pre>"

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
