---
type: llm
focus: trace
weight: 1
---

The response reports, as a critical finding, that a note stored without tags makes the v1 to v2 migration in src/store/migrations.js throw (n.tags.split on undefined), that load() in src/store/library.js swallows the error and returns an empty library, and that open() then writes the empty library over the stored notes, so the user loses them. It gives the file and line and the failure scenario.
