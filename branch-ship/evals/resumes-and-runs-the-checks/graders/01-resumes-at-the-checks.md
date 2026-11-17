---
type: llm
focus: trace
weight: 1
---

The skill reads the record and says that the review, the fix and the cleanup are done and that the only recorded check ran at an older commit than the tip. It does not run branch-review or branch-cleanup again: the state file still has exactly one "review" line and one "cleanup" line.
