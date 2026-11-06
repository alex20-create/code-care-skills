#!/usr/bin/env bash
# Builds the test repository in the current folder: a small journal app with
# four areas. The storage area swallows a failed write and reports success, so
# the screen says "Saved" when nothing was saved. The export area has a defect
# of its own (commas not quoted in CSV) that a one-area pass should not reach.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{ "name": "journal-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Journal app. Entries are kept in the browser's storage; there is no server.
- Areas: `src/storage` (saving and loading entries), `src/ui` (the status line and the entry list), `src/export` (CSV download), `src/util` (text helpers).
- Checks: `npm test`.
EOF

mkdir -p src/storage src/ui src/export src/util

cat > src/storage/entries.js <<'EOF'
const KEY = "journal.entries";

export function loadEntries(storage) {
  const raw = storage.getItem(KEY);
  return raw ? JSON.parse(raw) : [];
}

// Saves every entry. Returns true when the entries are stored.
export function saveEntries(storage, entries) {
  try {
    storage.setItem(KEY, JSON.stringify(entries));
  } catch (err) {
    console.debug("save skipped", err.name);
  }
  return true;
}
EOF

cat > src/ui/status.js <<'EOF'
import { saveEntries } from "../storage/entries.js";

// Called when the user presses Save; the text is shown in the status line.
export function onSave(storage, entries) {
  const ok = saveEntries(storage, entries);
  return ok ? "Saved" : "Could not save: free some space and try again";
}
EOF

cat > src/ui/list.js <<'EOF'
import { shorten } from "../util/text.js";

export function renderEntries(entries) {
  return entries.map((e) => `${e.date}  ${shorten(e.text, 40)}`).join("\n");
}
EOF

cat > src/export/csv.js <<'EOF'
export function toCsv(entries) {
  const rows = entries.map((e) => [e.date, e.text].join(","));
  return ["date,text", ...rows].join("\n");
}
EOF

cat > src/util/text.js <<'EOF'
export function shorten(text, max) {
  return text.length > max ? text.slice(0, max - 1) + "…" : text;
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { loadEntries } from "./src/storage/entries.js";
import { onSave } from "./src/ui/status.js";
import { toCsv } from "./src/export/csv.js";
const mem = new Map();
const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v) };
assert.equal(onSave(storage, [{ date: "2026-01-01", text: "hi" }]), "Saved");
assert.equal(loadEntries(storage).length, 1);
assert.equal(toCsv([{ date: "d", text: "t" }]), "date,text\nd,t");
console.log("ok");
EOF

git add -A
git commit -q -m "feat: journal storage, status line, list and export"
