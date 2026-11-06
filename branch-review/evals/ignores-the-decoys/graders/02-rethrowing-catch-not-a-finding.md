---
type: llm
focus: trace
weight: 1
---

The catch block in schedule (src/autosave.mjs) that resets the timer and rethrows is not reported as a swallowed or silent error.
