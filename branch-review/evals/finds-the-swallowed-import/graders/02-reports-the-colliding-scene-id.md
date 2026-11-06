---
type: llm
focus: trace
weight: 1
---

The findings include sceneId in src/import.mjs: two scenes whose titles differ only in case or spacing get the same id, so the second overwrites the first in the store while the message still counts both.
