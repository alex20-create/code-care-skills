---
type: llm
focus: trace
weight: 1
---

src/index.js no longer imports `unusedHelper`, and the `defaults` object has a single `theme` key whose value is "light" (the earlier "dark" one, which never took effect, is gone).
