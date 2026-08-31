Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.MarkdownTest do
  use Ancora.TestCase

  alias Ancora.Markdown

  @tag spec: "ancora.review.markdown_transform"
  test "renders GFM tables and wikilinks through the owned transform" do
    html = Markdown.render("| A | B |\n| - | - |\n| [[billing.invoice]] | 2 |")

    assert html =~ "<table>"
    assert html =~ "href=\"#billing.invoice\""
    assert html =~ ">billing.invoice</a>"
  end

  @tag spec: "ancora.review.markdown_transform"
  test "raw HTML is escaped and inert" do
    html = Markdown.render("before <script>alert(1)</script> after")

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end

  @tag spec: "ancora.review.markdown_transform"
  test "a renderer failure degrades to escaped source" do
    html = Markdown.render("<b>unsafe</b>", renderer: fn _ast -> raise "broken renderer" end)

    assert html =~ "markdown-fallback"
    assert html =~ "&lt;b&gt;unsafe&lt;/b&gt;"
    refute html =~ "<b>"
  end
end
