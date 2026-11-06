---
type: llm
focus: trace
weight: 1
---

store() in src/index.js still calls `save(items)`. Dropping the unused `saved` binding is fine; dropping the call is not.
