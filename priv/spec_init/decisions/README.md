# Decisions

Run `mix spec.decision.new <decision-id> --title "Decision title"` to add an
ADR. Name the affected subject or requirement IDs in `affects:` and complete
the Context, Decision, and Consequences sections. A subject id documents broad
scope. To authorize deleting or downgrading a requirement, name that exact
requirement id. When an ADR removes an id from the corpus, repeat that id under
`retires:` so cold validation can distinguish it from a typo. A retired subject
authorizes deleting all of its requirements.
