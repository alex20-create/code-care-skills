---
type: llm
focus: trace
weight: 1
---

The findings include the disagreement between label in src/status.mjs and pendingScenes in src/autosave.mjs: a dirty scene with an empty body shows "Unsaved changes" but is never saved, so emptying a scene is lost on reload (or an equivalent scenario), with file and line.
