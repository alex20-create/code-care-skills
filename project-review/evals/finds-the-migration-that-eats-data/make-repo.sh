#!/usr/bin/env bash
# Builds the test repository in the current folder: a small notes app whose
# data migration crashes on notes without tags, a load() that swallows the
# crash and saves an empty library over the user's data, a .env committed once
# and deleted later, and decoys that are untidy but not defects.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{ "name": "notes-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Notes app. The library lives in one stored document; `open()` loads it, upgrades it and saves it back.
- Checks: `npm test`. CI runs the same on every push.
EOF

cat > .env <<'EOF'
API_KEY=fixture-secret-4b8e21
EOF

git add -A
git commit -q -m "feat: project skeleton"

git rm -q --cached .env
rm .env
cat > .gitignore <<'EOF'
.env*
node_modules/
EOF

mkdir -p src/store src/ui src/util .github/workflows

cat > .github/workflows/test.yml <<'EOF'
name: test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test
EOF

cat > src/store/migrations.js <<'EOF'
// Step n upgrades a library at version n to version n + 1.
export const CURRENT = 3;

export const migrations = [
  // v1 -> v2: tags were one comma-separated string; they become a list.
  (lib) => ({ ...lib, version: 2, notes: lib.notes.map((n) => ({ ...n, tags: n.tags.split(",") })) }),
  // v2 -> v3: every note gets a pinned flag.
  (lib) => ({ ...lib, version: 3, notes: lib.notes.map((n) => ({ ...n, pinned: false })) }),
];

export function upgrade(lib) {
  let current = lib;
  while (current.version < CURRENT) current = migrations[current.version - 1](current);
  return current;
}
EOF

cat > src/store/library.js <<'EOF'
import { upgrade, CURRENT } from "./migrations.js";

export function load(stored) {
  try {
    return upgrade(stored ?? { version: CURRENT, notes: [] });
  } catch {
    return { version: CURRENT, notes: [] };
  }
}

// Loads the stored library, upgrades it and writes it back.
export function open(storage) {
  const lib = load(storage.read());
  storage.write(lib);
  return lib;
}
EOF

cat > src/ui/list.js <<'EOF'
import { formatDate } from "../util/format.js";

export function renderList(lib) {
  var rows = [];
  for (var i = 0; i < lib.notes.length; i++) {
    var n = lib.notes[i];
    // rows.push(n.title.toUpperCase());
    rows.push((n.pinned ? "* " : "") + n.title + " (" + formatDate(n.at) + ")");
  }
  return rows.join("\n");
}
EOF

cat > src/util/format.js <<'EOF'
export function formatDate(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function oldFormat(ms) {
  return String(ms);
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { open } from "./src/store/library.js";
import { renderList } from "./src/ui/list.js";
let saved = null;
const storage = {
  read: () => ({ version: 1, notes: [{ title: "a", at: 0, tags: "x,y" }] }),
  write: (lib) => { saved = lib; },
};
const lib = open(storage);
assert.deepEqual(lib.notes[0].tags, ["x", "y"]);
assert.equal(saved.version, 3);
assert.equal(renderList(lib), "a (1970-01-01)");
console.log("ok");
EOF

git add -A
git commit -q -m "feat: notes library with migrations"
