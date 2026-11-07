#!/usr/bin/env bash
# Builds the test repository in the current folder: the journal app with four
# areas, an earlier review report in .review/ (excluded from git) that covered
# storage and ui and found one critical defect in storage, and, after that
# review, a merged fix branch that changes the storage catch. Resuming should
# mark storage stale, keep ui reviewed and treat the finding as fixed, to be
# confirmed.
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
BASE=$(git rev-parse --short HEAD)

# The earlier review, written at BASE and kept out of git.
mkdir -p .review
echo ".review/" >> .git/info/exclude
cat > .review/report.md <<'EOF'
# Project review: journal-fixture (2026-11-05)

## Summary
Folder: . · started at __BASE__ (clean)
Coverage: 2 of 4 areas reviewed · 0 stale · 2 not reached
Findings: 1 critical · 0 important · 0 minor

## Areas
| # | Area | Paths | Lines | Why it ranks here | Status | Commit |
|---|---|---|---|---|---|---|
| 1 | Storage | src/storage/ | 16 | Stored data: save and load paths | reviewed | __BASE__ |
| 2 | Status line and list | src/ui/ | 12 | Boundary: what the user is told after a save | reviewed | __BASE__ |
| 3 | Export | src/export/ | 4 | Boundary: data leaves the app as a file | not reached | |
| 4 | Text helpers | src/util/ | 3 | Everything else | not reached | |

No secret files in the history.

## Findings
1. **Critical** · `src/storage/entries.js:10` · a failed save is reported as saved · area 1
   Scenario: storage full → `setItem` throws → the catch logs at debug level and the function still returns true → `onSave` shows "Saved" and the entry is lost on reload.
   Verified: traced
   Fix (not applied): return false from the catch so the status line shows its own failure message.

## Possible
- `src/storage/entries.js:5` · `JSON.parse` on a damaged value would throw on load; whether anything above catches it depends on the caller, which is outside the reviewed areas.

## Contracts to check
- 1 produces the boolean from `saveEntries` that 2 consumes in `onSave`: confirmed in area 2, it holds once finding 1 is fixed.

## Already known
- none

## Looked at and found sound
- 2: `renderEntries` shortens text through `shorten` and keeps one entry per line; the status line has both messages wired.

## Recommended order
1. `fix/save-result` · finding 1 · `src/storage/entries.js` · checked with `branch-review` before merging.
EOF
sed -i "s/__BASE__/$BASE/g" .review/report.md

# The fix, merged after the review.
git checkout -q -b fix/save-result
sed -i 's/    console.debug("save skipped", err.name);/    return false;/' src/storage/entries.js
git commit -qam "fix: report a failed save instead of claiming success"
git checkout -q main
git merge -q --no-ff fix/save-result -m "Merge branch 'fix/save-result'"
