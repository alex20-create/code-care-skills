#!/usr/bin/env bash
# Builds the test repository in the current folder: main with a scene store and
# a status label, and feat/autosave adding an autosave module with one real
# defect (the label and the autosave disagree about which scenes count as
# unsaved) and several decoys that look like defects but are not.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{
  "name": "autosave-fixture",
  "private": true,
  "type": "module",
  "scripts": { "test": "node test.mjs" }
}
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Local-first scene editor. Scenes live in the store and nowhere else.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
- Style: arrow functions are the project's convention; errors are thrown, not logged.
- Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
EOF

mkdir -p src

cat > src/store.mjs <<'EOF'
const saved = new Map();

export const persist = (scenes) => {
  for (const scene of scenes) saved.set(scene.id, { ...scene, dirty: false });
};

export const persisted = () => [...saved.values()];

export const reset = () => saved.clear();
EOF

cat > src/status.mjs <<'EOF'
const FLAGS = ["dirty", "locked"];

export const hasFlag = (scene, flag) => FLAGS.includes(flag) && scene[flag] === true;

export const label = (scenes) =>
  scenes.some((scene) => hasFlag(scene, "dirty")) ? "Unsaved changes" : "All changes saved";
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { label } from "./src/status.mjs";

assert.equal(label([{ id: "a", body: "x", dirty: false }]), "All changes saved");
assert.equal(label([{ id: "a", body: "x", dirty: true }]), "Unsaved changes");
console.log("ok");
EOF

git add -A
git commit -q -m "feat: scene store and status label"

git switch -q -c feat/autosave

cat > src/autosave.mjs <<'EOF'
import { persist } from "./store.mjs";

let timer = null;
let lock = false;

const acquire = () => {
  if (lock) throw new Error("autosave already running");
  lock = true;
};

const release = () => {
  lock = false;
};

export const pendingScenes = (scenes) =>
  scenes.filter((scene) => scene.dirty && scene.body.length > 0);

export const save = (scenes) => {
  acquire();
  try {
    const pending = pendingScenes(scenes);
    if (pending.length > 0) persist(pending);
    return pending.length;
  } finally {
    release();
  }
};

export const schedule = (getScenes, delayMs = 800) => {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => {
    try {
      save(getScenes());
    } catch (error) {
      timer = null;
      throw error;
    }
    timer = null;
  }, delayMs);
  return () => {
    if (timer !== null) clearTimeout(timer);
    timer = null;
  };
};
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { label } from "./src/status.mjs";
import { save } from "./src/autosave.mjs";
import { persisted, reset } from "./src/store.mjs";

assert.equal(label([{ id: "a", body: "x", dirty: false }]), "All changes saved");
assert.equal(label([{ id: "a", body: "x", dirty: true }]), "Unsaved changes");

reset();
assert.equal(save([{ id: "a", body: "x", dirty: true }, { id: "b", body: "y", dirty: false }]), 1);
assert.equal(persisted().length, 1);
assert.equal(persisted()[0].dirty, false);
console.log("ok");
EOF

git add -A
git commit -q -m "feat: autosave dirty scenes after a pause"
