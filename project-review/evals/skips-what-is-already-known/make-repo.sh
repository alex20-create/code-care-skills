#!/usr/bin/env bash
# Builds the test repository in the current folder: a small catalogue app with
# two defects the project already records (one in CLAUDE.md, one in the Pending
# of an earlier cleanup report kept out of git) and one it does not know about:
# the store returns undefined for a missing item while the detail view checks
# for null, so opening a deleted item crashes.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{ "name": "known-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Catalogue app: a list of parts, a detail view, a sync with the server.
- Checks: `npm test`.

## Known issues
- `sortParts` in src/list.js compares names as text, so "part10" sorts before "part2". Fix planned for the next release; do not report it again.
EOF

mkdir -p src .cleanup

cat > src/store.js <<'EOF'
const items = new Map();

export function putItem(item) {
  items.set(item.id, item);
}

export function deleteItem(id) {
  items.delete(id);
}

// Returns the item, or null when there is no item with that id.
export function getItem(id) {
  return items.get(id);
}
EOF

cat > src/detail.js <<'EOF'
import { getItem } from "./store.js";

// Title shown at the top of the detail view, reached from links and history.
export function detailTitle(id) {
  const item = getItem(id);
  if (item === null) return "Item not found";
  return item.title.toUpperCase();
}
EOF

cat > src/list.js <<'EOF'
export function sortParts(names) {
  return [...names].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}
EOF

cat > src/api.js <<'EOF'
export async function fetchAll(fetchFn, url) {
  const res = await fetchFn(url);
  return res.json();
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { putItem } from "./src/store.js";
import { detailTitle } from "./src/detail.js";
import { sortParts } from "./src/list.js";
putItem({ id: 1, title: "bolt" });
assert.equal(detailTitle(1), "BOLT");
assert.deepEqual(sortParts(["b", "a"]), ["a", "b"]);
console.log("ok");
EOF

cat > .cleanup/report.md <<'EOF'
# Cleanup report: known-fixture

## Pending (deliberately not applied)
1. **Important** · src/api.js:2-3 · fetchAll never checks res.ok, so a 500 from the server is parsed as if it were data. Scenario: the server fails, the error page's JSON body becomes the catalogue. Checked: read.
EOF
printf '.cleanup/\n' >> .git/info/exclude

git add -A
git commit -q -m "feat: catalogue store, detail view and sync"
