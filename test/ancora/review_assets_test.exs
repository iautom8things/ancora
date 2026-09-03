Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ReviewAssetsTest do
  use Ancora.TestCase

  @asset_digests %{
    "prism-css.min.js" => "8c9760dba7f26ea842016919544dd9b73a78a36d5b07a1e9842c333ed18ab6ae",
    "prism-diff.min.js" => "f16816fb2242a84c6ff6715a48c6d0a3e469e3250912cb9f1b755ca537d02f48",
    "prism-elixir.min.js" => "e1f6357ad3271d25ad5a2af8d34d93882cec605e98ec719499ee9ebec44ef4ce",
    "prism-erlang.min.js" => "7612f02966570909503ca4692e355c90efc9e5ac054331a4d8b9457f97fca512",
    "prism-json.min.js" => "956d86baa5ae7ec4106758f354ac2d140bdcd7fc103dece02f73ed12b8d663e4",
    "prism-markdown.min.js" => "9f1166a087d9a9ffb3a833f2bccbe00920b55b41ade02a0b3054b7ab5fbc70ea",
    "prism-markup.min.js" => "879fc9d256c352d980e053857fa707330853b8bfb67ce284ea661a24dec5756e",
    "prism-yaml.min.js" => "719c8e8b8c344dc9de510c729f65ba840b1502a0a8e7e25e2ad19ee715f65c02",
    "prism.css" => "928e23e6b9fcef82c5f1d1f05b6f7fc5a6e187c60195e59fbf16fc9d071ee057",
    "prism.min.js" => "9c86a9d6e2e92e4b9d1241bdef2367a31eaf70653199981b0d73c0defbe3a135"
  }

  @tag spec: "ancora.review.prism_carried"
  test "Prism assets match reviewed bytes and grammar ownership" do
    root = Path.expand("../..", __DIR__)
    asset_root = Path.join(root, "priv/spec_review_assets")

    files =
      asset_root |> Path.join("*") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()

    assert File.read!(Path.join(asset_root, "prism.min.js")) =~ "MIT license"
    notice = File.read!(Path.join(root, "NOTICE"))
    spec = File.read!(Path.join(root, ".spec/specs/ancora.review.spec.md"))

    assert notice =~ "PrismJS 1.29.0"
    assert notice =~ "Core Prism supplies markup, css, and javascript."
    assert spec =~ "Core Prism supplies markup,\n    css, and javascript."

    [_, notice_grammars] = Regex.run(~r/support only ([^.]+)\./, notice)
    [_, spec_grammars] = Regex.run(~r/trimmed to ([^.]+)\./, spec)
    assert normalize_grammar_list(notice_grammars) == normalize_grammar_list(spec_grammars)

    assert files ==
             Enum.sort(
               ~w(prism-css.min.js prism-diff.min.js prism-elixir.min.js prism-erlang.min.js prism-json.min.js prism-markdown.min.js prism-markup.min.js prism-yaml.min.js prism.css prism.min.js)
             )

    assert Map.new(files, fn file -> {file, sha256(Path.join(asset_root, file))} end) ==
             @asset_digests
  end

  test "NOTICE limits append-only authorization to requirement ids" do
    notice = Path.expand("../../NOTICE", __DIR__) |> File.read!()

    assert notice =~ "authorization is an accepted ADR whose affects: names the requirement;"
    assert notice =~ "a subject id alone does not authorize the change"
    refute notice =~ "or its subject; no change_type"
  end

  defp sha256(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp normalize_grammar_list(list) do
    list
    |> String.replace("\n", " ")
    |> String.replace("and ", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end
end
