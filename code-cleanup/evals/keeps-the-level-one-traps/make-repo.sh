#!/usr/bin/env bash
# Builds the test repository in the current folder: main only, with two things
# that really are unused and three that only look unused. The tests cover none
# of the three traps, so removing one would still pass them.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{ "name": "traps-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Checks: `npm test` (fast, milliseconds). There are no end-to-end tests and no dev server.
- Commits: Conventional Commits, imperative, lowercase, English.
EOF

mkdir -p src

cat > src/polyfill.js <<'EOF'
// Marks the app as ready for the embedding page, which polls this flag.
globalThis.appReady = true;
EOF

cat > src/store.js <<'EOF'
export const log = [];

export function save(items) {
  log.push(items.length);
  return log.length;
}
EOF

cat > src/util.js <<'EOF'
export function double(x) {
  return x * 2;
}

export function unusedHelper() {
  return 1;
}
EOF

cat > src/i18n.js <<'EOF'
export const messages = {
  "status.open": "Open",
  "status.closed": "Closed",
  "legacy.banner": "Welcome to the old site",
};

export function t(key) {
  return messages[key] ?? key;
}
EOF

cat > src/index.js <<'EOF'
import "./polyfill.js";
import { double, unusedHelper } from "./util.js";
import { save } from "./store.js";
import { t } from "./i18n.js";

const defaults = { theme: "dark", size: 2, theme: "light" };

export function settings() {
  return { ...defaults };
}

export function label(state) {
  return t("status." + state);
}

export function store(items) {
  const saved = save(items);
  return items.map(double);
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { settings, label, store } from "./src/index.js";
assert.equal(settings().size, 2);
assert.deepEqual(store([1, 2]), [2, 4]);
assert.equal(typeof label("open"), "string");
console.log("ok");
EOF

git add -A
git commit -q -m "feat: first version"
