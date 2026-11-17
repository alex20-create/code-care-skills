---
type: llm
focus: trace
weight: 1
---

The skill reads the existing record and goes on from the missing checks: it does not run branch-review again, the state file still has exactly one "review" line, and no new fix or cleanup commit was made.
