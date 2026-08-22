# Admin — Recommendations Sandbox

Interactive admin tool for exploring the recommendation engine. Supports
contact search, ad-hoc data entry, and model comparison for testing and
debugging relevance scoring.

```spec-meta
id: admin.recommendations
kind: feature
status: active
summary: Admin sandbox for testing recommendation engine with contact search and model comparison
surface:
  - lib/engage_web/live/admin/recommendations.ex
decisions: []
realized_by:
  api_boundary:
    - "EngageWeb.AdminLive.Recommendations.mount/3"
    - "EngageWeb.AdminLive.Recommendations.handle_params/3"
    - "EngageWeb.AdminLive.Recommendations.handle_event/3"
    - "EngageWeb.AdminLive.Recommendations.render/1"
```

```spec-requirements
- id: admin.recommendations.contact_search
  priority: must
  statement: >
    The sandbox provides contact search to select a source contact for
    generating recommendations.

- id: admin.recommendations.model_comparison
  priority: must
  statement: >
    Admins can compare recommendation results across different models
    to evaluate scoring differences.

- id: admin.recommendations.state_persistence
  priority: should
  statement: >
    The sandbox persists the last-used contact and model to browser
    localStorage and restores them when the user returns to the page
    without URL parameters.
```

```spec-verification
- kind: source_file
  target: test/engage_web/live/admin/recommendations_test.exs
  execute: true
  covers:
    - admin.recommendations.contact_search
    - admin.recommendations.model_comparison

- kind: source_file
  target: assets/js/hooks/sandbox_persist.js
  execute: false
  covers:
    - admin.recommendations.state_persistence
```
