defmodule Ancora.Review.Html do
  @moduledoc "Renders the review view-model as one self-contained HTML document."

  alias Ancora.Markdown

  @spec render(map()) :: iodata()
  def render(view) do
    [
      "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
      "<title>Spec review</title><style>",
      css(),
      prism_css(),
      "</style></head><body><div class=\"shell\">",
      rail(view),
      "<main>",
      overview(view),
      Enum.map(view.subjects, &subject/1),
      decisions(view.decisions_changed),
      all_files(view.all_changes),
      "</main></div><script>",
      prism_js(),
      interaction_js(),
      "</script></body></html>"
    ]
  end

  defp rail(view) do
    [
      "<aside><h1>Review</h1><nav>",
      nav("Overview", "overview"),
      nav("Decisions changed", "decisions"),
      "<h2>Affected subjects</h2>",
      Enum.map(view.subjects, &nav(&1.id, anchor(&1.id))),
      nav("Outside the spec system", "outside"),
      nav("All files", "all-files"),
      nav("Spec health", "spec-health"),
      "</nav></aside>"
    ]
  end

  defp nav(label, id), do: ["<a href=\"#", escape(id), "\">", escape(label), "</a>"]

  defp overview(view) do
    verdict = Atom.to_string(view.verdict)

    [
      "<section id=\"overview\"><header><div><p class=\"eyebrow\">Change review</p>",
      "<h2>Overview</h2></div><span class=\"chip ",
      verdict,
      "\">",
      verdict,
      "</span></header>",
      "<p class=\"meta\">base=",
      escape(view.meta.base_ref),
      " head=",
      escape(view.meta.head_ref),
      "</p>",
      delta(view.findings_delta),
      triage(view.triage),
      outside(view.outside_changes),
      spec_health(view.spec_health),
      "</section>"
    ]
  end

  defp delta(delta) do
    [
      "<div class=\"delta-grid\">",
      delta_group("Introduced", delta.introduced),
      delta_group("Pre-existing", delta.pre_existing),
      delta_group("Resolved", delta.resolved),
      "</div>"
    ]
  end

  defp delta_group(label, findings) do
    [
      "<div class=\"panel\"><h3>",
      label,
      " <span>",
      Integer.to_string(length(findings)),
      "</span></h3>",
      findings(findings),
      "</div>"
    ]
  end

  defp triage(groups) do
    [
      "<section class=\"panel triage\"><h3>Triage</h3>",
      Enum.map([:error, :warning, :info], fn severity ->
        items = Map.get(groups, severity, [])

        [
          "<div><strong>",
          Atom.to_string(severity),
          "</strong> ",
          Integer.to_string(length(items)),
          "</div>"
        ]
      end),
      "</section>"
    ]
  end

  defp outside(files) do
    [
      "<section id=\"outside\" class=\"panel\"><h3>Outside the spec system</h3>",
      file_links(files),
      "</section>"
    ]
  end

  defp spec_health(health) do
    [
      "<section id=\"spec-health\" class=\"panel\"><h3>Spec health</h3><p>",
      Integer.to_string(health.subjects),
      " subjects, ",
      Integer.to_string(health.requirements),
      " requirements, ",
      Integer.to_string(health.errors),
      " errors, ",
      Integer.to_string(health.warnings),
      " warnings</p></section>"
    ]
  end

  defp subject(subject) do
    [
      "<section class=\"subject\" id=\"",
      anchor(subject.id),
      "\"><header><div><p class=\"eyebrow\">Subject</p><h2>",
      escape(subject.title),
      "</h2><code>",
      escape(subject.id),
      "</code></div>",
      findings(subject.findings),
      "</header>",
      "<div class=\"summary\">",
      Markdown.render(subject.summary),
      "</div>",
      "<div class=\"pivots\" role=\"tablist\">",
      pivot_button("Spec", true),
      pivot_button("Code", false),
      pivot_button("Decisions", false),
      "</div><div class=\"pivot active\" data-pivot=\"Spec\">",
      spec(subject),
      "</div>",
      "<div class=\"pivot\" data-pivot=\"Code\">",
      code(subject.code),
      "</div>",
      "<div class=\"pivot\" data-pivot=\"Decisions\">",
      decision_refs(subject.decision_refs),
      "</div>",
      "</section>"
    ]
  end

  defp pivot_button(name, active?) do
    class = if active?, do: " class=\"active\"", else: ""
    ["<button type=\"button\" data-target=\"", name, "\"", class, ">", name, "</button>"]
  end

  defp spec(subject) do
    [
      "<h3>Requirements</h3>",
      Enum.map(subject.requirements, fn requirement ->
        [
          "<article class=\"claim\"><code>",
          escape(field(requirement, :id)),
          "</code><p>",
          Markdown.render(field(requirement, :statement)),
          "</p></article>"
        ]
      end),
      "<h3>Scenarios</h3>",
      Enum.map(subject.scenarios, fn scenario ->
        ["<article class=\"claim\"><code>", escape(field(scenario, :id)), "</code></article>"]
      end)
    ]
  end

  defp code(code) do
    [
      "<h3>Watched interface</h3>",
      empty_or(code.watched_interface, "No watched interface changes.", &watched_card/1),
      "<h3>Supporting changes</h3>",
      empty_or(code.supporting_changes, "No supporting changes.", &file_diff/1),
      "<h3>Test changes</h3>",
      binding_list("Added bindings", code.added_bindings),
      binding_list("Removed bindings", code.removed_bindings),
      empty_or(code.test_changes, "No test changes.", &file_diff/1)
    ]
  end

  defp watched_card(card) do
    [
      "<article class=\"watched\"><header><code>",
      escape(card.binding),
      "</code><span class=\"badge error\">",
      Atom.to_string(card.badge),
      "</span></header><a href=\"#file-",
      anchor(card.file),
      "\">",
      escape(card.file),
      "</a>",
      diff(card.lines),
      "</article>"
    ]
  end

  defp binding_list(_label, []), do: ""

  defp binding_list(label, bindings),
    do: [
      "<h4>",
      label,
      "</h4><ul>",
      Enum.map(bindings, &["<li><code>", escape(&1), "</code></li>"]),
      "</ul>"
    ]

  defp decisions(items) do
    [
      "<section id=\"decisions\"><h2>Decisions changed</h2>",
      empty_or(items, "No decisions changed.", &decision/1),
      "</section>"
    ]
  end

  defp decision(item),
    do: [
      "<article class=\"panel\"><code>",
      escape(item.id),
      "</code><p>",
      escape(item.title),
      "</p></article>"
    ]

  defp decision_refs([]), do: "<p>No decisions referenced.</p>"

  defp decision_refs(refs),
    do: [
      "<ul>",
      Enum.map(refs, &["<li><a href=\"#", anchor(&1), "\">", escape(&1), "</a></li>"]),
      "</ul>"
    ]

  defp all_files(changes) do
    [
      "<section id=\"all-files\"><h2>All files</h2>",
      Enum.map(changes, &file_diff/1),
      "</section>"
    ]
  end

  defp file_diff(change) do
    [
      "<article class=\"file\" id=\"file-",
      anchor(change.file),
      "\"><h4>",
      escape(change.file),
      "</h4>",
      diff(change.lines),
      "</article>"
    ]
  end

  defp diff(lines) do
    [
      "<pre class=\"diff\"><code class=\"language-diff\">",
      Enum.map(lines, fn {kind, line} ->
        ["<span class=\"", Atom.to_string(kind), "\">", escape(line), "</span>\n"]
      end),
      "</code></pre>"
    ]
  end

  defp findings([]), do: "<p class=\"empty\">None</p>"
  defp findings(items), do: Enum.map(items, &finding/1)

  defp finding(finding) do
    [
      "<details class=\"finding\"><summary><span class=\"badge ",
      Atom.to_string(finding.severity || :info),
      "\">",
      escape(finding.code),
      "</span></summary><p>",
      escape(finding.message),
      "</p></details>"
    ]
  end

  defp empty_or([], message, _renderer), do: ["<p class=\"empty\">", message, "</p>"]
  defp empty_or(items, _message, renderer), do: Enum.map(items, renderer)
  defp file_links([]), do: "<p class=\"empty\">None</p>"
  defp file_links(files), do: ["<ul>", Enum.map(files, &["<li>", escape(&1), "</li>"]), "</ul>"]

  defp field(item, key) when is_struct(item), do: Map.get(item, key) || ""

  defp field(item, key) when is_map(item),
    do: Map.get(item, key) || Map.get(item, Atom.to_string(key)) || ""

  defp anchor(value),
    do: value |> to_string() |> String.replace(~r/[^a-zA-Z0-9_-]/, "-") |> escape()

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp prism_css, do: asset("prism.css")

  defp prism_js do
    ~w(prism.min.js prism-elixir.min.js prism-erlang.min.js prism-diff.min.js prism-yaml.min.js prism-markdown.min.js prism-json.min.js prism-markup.min.js prism-css.min.js)
    |> Enum.map(&asset/1)
  end

  defp asset(name) do
    case :code.priv_dir(:ancora) do
      dir when is_list(dir) ->
        File.read!(Path.join([List.to_string(dir), "spec_review_assets", name]))

      _ ->
        ""
    end
  end

  defp interaction_js do
    """
    document.querySelectorAll('.pivots button').forEach(function(button) {
      button.addEventListener('click', function() {
        var section = button.closest('.subject');
        section.querySelectorAll('.pivots button').forEach(function(item) { item.classList.remove('active'); });
        section.querySelectorAll('.pivot').forEach(function(item) { item.classList.remove('active'); });
        button.classList.add('active');
        section.querySelector('[data-pivot="' + button.dataset.target + '"]').classList.add('active');
      });
    });
    if (window.Prism) { Prism.highlightAll(); }
    """
  end

  defp css do
    """
    :root{color-scheme:light dark;--bg:#f6f3ed;--panel:#fffdf8;--ink:#25231f;--muted:#706b62;--line:#d9d2c5;--accent:#5b4bc4;--ok:#16784a;--bad:#b13c32;--warn:#9a6200}
    @media(prefers-color-scheme:dark){:root{--bg:#171613;--panel:#22201c;--ink:#f3eee4;--muted:#aaa398;--line:#3b3730;--accent:#a99cff;--ok:#66d19e;--bad:#ff8b80;--warn:#efbd5d}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,sans-serif}.shell{display:grid;grid-template-columns:260px minmax(0,1fr);min-height:100vh}aside{border-right:1px solid var(--line);padding:24px;position:sticky;top:0;height:100vh;overflow:auto}aside h1{font-size:18px}aside h2{font-size:11px;text-transform:uppercase;color:var(--muted);margin-top:24px}nav a{display:block;color:var(--ink);padding:6px 0;text-decoration:none}main{width:min(1120px,100%);padding:42px;margin:auto}section{scroll-margin-top:24px;margin-bottom:56px}.subject,.panel,.file{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:20px;margin:14px 0}header{display:flex;align-items:flex-start;justify-content:space-between;gap:20px}.eyebrow{color:var(--muted);font-size:11px;letter-spacing:.12em;text-transform:uppercase;margin:0}.chip,.badge{border:1px solid currentColor;border-radius:999px;padding:3px 9px;font-size:12px}.pass{color:var(--ok)}.fail,.error{color:var(--bad)}.warning{color:var(--warn)}.info{color:var(--accent)}.meta,.empty{color:var(--muted)}.delta-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.pivots{display:flex;gap:6px;border-bottom:1px solid var(--line);margin-top:20px}.pivots button{appearance:none;border:0;background:none;color:var(--muted);padding:10px 14px}.pivots button.active{color:var(--accent);border-bottom:2px solid var(--accent)}.pivot{display:none;padding-top:16px}.pivot.active{display:block}.claim,.watched{border-left:3px solid var(--line);padding:8px 14px;margin:10px 0}.diff{overflow:auto;background:#111;color:#ddd;padding:14px;border-radius:7px;font-size:12px}.diff span{display:block}.diff .add{color:#8ee3ab;background:#163522}.diff .del{color:#ff9b92;background:#3c1e1b}.diff .hunk_header{color:#a99cff}.finding{display:inline-block;margin:4px}.finding p{max-width:720px}.summary{max-width:76ch}@media(max-width:800px){.shell{display:block}aside{position:static;height:auto;border-right:0;border-bottom:1px solid var(--line)}main{padding:22px}.delta-grid{grid-template-columns:1fr}}
    """
  end
end
