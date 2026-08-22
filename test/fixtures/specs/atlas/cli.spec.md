# CLI

Mix task interface for query and maintenance commands.

```spec-meta
id: cli
kind: module
status: active
summary: Mix tasks for search, stats, graph, filter, impact, lookup, and schema operations. Surviving tasks accept --kb NAME and read registered KBs directly from Atlas.KB.
surface:
  - lib/atlas/cli/formatter.ex
  - lib/mix/tasks/atlas.search.ex
  - lib/mix/tasks/atlas.stats.ex
  - lib/mix/tasks/atlas.graph.ex
  - lib/mix/tasks/atlas.filter.ex
  - lib/mix/tasks/atlas.impact.ex
  - lib/mix/tasks/atlas.lookup.ex
  - lib/mix/tasks/atlas.schema.ex
realized_by:
  implementation:
    - "Mix.Tasks.Atlas.Search.run/1"
    - "Mix.Tasks.Atlas.Stats.run/1"
    - "Mix.Tasks.Atlas.Graph.run/1"
    - "Mix.Tasks.Atlas.Filter.run/1"
    - "Mix.Tasks.Atlas.Impact.run/1"
    - "Mix.Tasks.Atlas.Lookup.run/1"
    - "Mix.Tasks.Atlas.Schema.run/1"
    - "Atlas.CLI.Formatter.resolve_format/1"
    - "Atlas.CLI.Formatter.compact_node/1"
    - "Atlas.CLI.Formatter.compact_search_result/1"
    - "Atlas.CLI.Formatter.compact_lookup_result/2"
    - "Atlas.CLI.Formatter.compact_impact_group/1"
    - "Atlas.CLI.Formatter.compact_graph_node/2"
    - "Atlas.CLI.Formatter.compact_schema/1"
    - "Atlas.CLI.Formatter.compact_stats/1"
decisions:
  - adr-001
```

## Requirements

```spec-requirements
- id: cli.kb_resolution
  statement: Surviving KB-aware mix tasks shall accept --kb NAME and resolve it by calling Atlas.KB.get/1; unknown KB names shall fail with a clear CLI error instead of creating a KB implicitly.
  priority: must
  stability: stable

- id: cli.mix_tasks
  statement: Mix tasks shall be provided for search, stats, graph, filter, impact, lookup, and schema operations.
  priority: must
  stability: stable

- id: cli.formatting
  statement: The formatter shall present query results, stats, and graph data in human-readable CLI output.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: lib/atlas/cli/formatter.ex
  covers:
    - cli.formatting

- kind: source_file
  target: lib/mix/tasks/atlas.search.ex
  covers:
    - cli.kb_resolution
    - cli.mix_tasks
```
