---
id: ancora.decision.reject_unsafe_tree_paths
status: accepted
date: 2026-09-04
affects:
  - ancora.derive
---

# Reject a base tree with an unsafe path component

## Context

`git mktree` accepts an entry literally named `..`, and `git ls-tree -r`
emits it verbatim. Git only normalizes a `<rev>:<path>` string that starts
with `./` or `../`; an embedded `..` matches a tree entry by name, so
`a/../../evil.txt` reads fine and `Path.join` leaves the component in place.
`Ancora.BaseView.materialize/3` then wrote that blob outside its temporary
root, and the cleanup in Gate and Review never removed it. GitHub rejects
such trees on push, so the hole is reachable from a local checkout of an
untrusted repository.

## Decision

BaseView validates every listed path before it reads a blob or creates the
temporary root. A `..`, `.`, or empty slash-delimited component rejects the
entire tree with `{:env, message}`; Gate and Review return that result
without raising. Matching is per component, so a name such as `foo..bar`
stays valid. The check lives in BaseView because it is the one caller that
writes git-supplied paths to disk. Read-only Git callers are unchanged.

## Consequences

Positive: a hostile tree produces an environment verdict and zero writes
outside the root, with no new module or process.

Negative: a repository whose base tree carries a malformed entry cannot be
gated until the tree is repaired. That repository is hostile or corrupt, not
unlucky, so refusing the whole tree is the intended outcome.
