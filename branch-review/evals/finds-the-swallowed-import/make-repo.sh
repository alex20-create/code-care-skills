#!/usr/bin/env bash
# Builds the test repository in the current folder: main with a small scene
# store and one old swallowed error (legacy.mjs, out of scope), and feat/import
# adding an importer with two defects: a parse error turned into an empty
# import, and a scene id that makes distinct titles collide.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{
  "name": "import-fixture",
  "private": true,
  "type": "module",
  "scripts": { "test": "node test.mjs" },
  "dependencies": { "dexie": "^4.0.0" },
  "devDependencies": { "vitest": "^5.0.0" }
}
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Local-first screenplay notes. Scenes live in the store and nowhere else.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
- Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
EOF

mkdir -p src

cat > src/store.mjs <<'EOF'
const scenes = new Map();

export function saveScenes(list) {
  for (const scene of list) scenes.set(scene.id, scene);
}

export function allScenes() {
  return [...scenes.values()];
}

export function clear() {
  scenes.clear();
}
EOF

cat > src/legacy.mjs <<'EOF'
// Old loader kept for the migration from the first file format.
export function oldLoad(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { saveScenes, allScenes, clear } from "./src/store.mjs";

clear();
saveScenes([{ id: "scene:dawn", title: "Dawn", body: "a" }]);
assert.equal(allScenes().length, 1);
console.log("ok");
EOF

git add -A
git commit -q -m "feat: scene store"

git switch -q -c feat/import

cat > src/import.mjs <<'EOF'
export function sceneId(title) {
  return "scene:" + title.trim().toLowerCase().replace(/\s+/g, "-");
}

export function importScenes(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return [];
  }
  if (!parsed || !Array.isArray(parsed.scenes)) return [];
  return parsed.scenes.map((scene) => ({
    id: sceneId(scene.title),
    title: scene.title,
    body: scene.body ?? "",
  }));
}
EOF

cat > src/ui.mjs <<'EOF'
import { importScenes } from "./import.mjs";
import { saveScenes } from "./store.mjs";

export function importButton(text) {
  const scenes = importScenes(text);
  if (scenes.length === 0) return "Nothing to import";
  saveScenes(scenes);
  return `${scenes.length} scenes imported`;
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { saveScenes, allScenes, clear } from "./src/store.mjs";
import { importScenes } from "./src/import.mjs";
import { importButton } from "./src/ui.mjs";

clear();
saveScenes([{ id: "scene:dawn", title: "Dawn", body: "a" }]);
assert.equal(allScenes().length, 1);

const text = JSON.stringify({ scenes: [{ title: "Night", body: "b" }, { title: "Morning", body: "c" }] });
assert.equal(importScenes(text).length, 2);
clear();
assert.equal(importButton(text), "2 scenes imported");
assert.equal(allScenes().length, 2);
console.log("ok");
EOF

git add -A
git commit -q -m "feat: import scenes from a json file"
