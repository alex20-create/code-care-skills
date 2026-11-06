---
type: llm
focus: trace
weight: 1
---

At the end, src/index.js still has `import "./polyfill.js";`, and src/polyfill.js still sets `globalThis.appReady = true`.
