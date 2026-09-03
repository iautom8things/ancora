Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ReviewAssetsTest do
  use Ancora.TestCase

  @tag spec: "ancora.review.prism_carried"
  test "Prism carries its MIT header and only the selected component files" do
    root = Path.expand("../..", __DIR__)
    asset_root = Path.join(root, "priv/spec_review_assets")

    files =
      asset_root |> Path.join("*") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()

    assert File.read!(Path.join(asset_root, "prism.min.js")) =~ "MIT license"
    assert File.read!(Path.join(root, "NOTICE")) =~ "PrismJS 1.29.0"

    assert files ==
             Enum.sort(
               ~w(prism-css.min.js prism-diff.min.js prism-elixir.min.js prism-erlang.min.js prism-json.min.js prism-markdown.min.js prism-markup.min.js prism-yaml.min.js prism.css prism.min.js)
             )
  end
end
