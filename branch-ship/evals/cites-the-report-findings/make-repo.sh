#!/usr/bin/env bash
# Builds the test repository in the current folder: the journal app on main
# with three defects, and a project-review report in .review/ (excluded from
# git) whose decision stop put findings 1 and 3 in fix branch 1 and deferred
# finding 2. A copy of the report is kept inside .git so a grader can tell
# whether the report was written to.
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
- Branches: `fix/<short-description>` for fixes. Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
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

// One line per entry; the text is cut to fit a 40-character column.
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
// Cuts text to at most max characters, ending in an ellipsis when cut.
export function shorten(text, max) {
  return text.length > max ? text.slice(0, max) + "…" : text;
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { loadEntries } from "./src/storage/entries.js";
import { onSave } from "./src/ui/status.js";
import { toCsv } from "./src/export/csv.js";
import { shorten } from "./src/util/text.js";
const mem = new Map();
const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v) };
assert.equal(onSave(storage, [{ date: "2026-01-01", text: "hi" }]), "Saved");
assert.equal(loadEntries(storage).length, 1);
assert.equal(toCsv([{ date: "d", text: "t" }]), "date,text\nd,t");
assert.equal(shorten("short", 40), "short");
console.log("ok");
EOF

git add -A
git commit -q -m "feat: journal storage, status line, list and export"
BASE=$(git rev-parse --short HEAD)

mkdir -p .review
echo ".review/" >> .git/info/exclude
cat > .review/report.md <<'EOF'
# Project review: journal-fixture (2026-11-16)

## Summary
Folder: . · started at __BASE__ (clean)
Coverage: 4 of 4 areas reviewed · 0 stale · 0 not reached
Findings: 1 critical · 1 important · 1 minor
Cost: pass 1 · estimated 60 · read 60

## Areas
| # | Area | Paths | Lines | Why it ranks here | Status | Commit |
|---|---|---|---|---|---|---|
| 1 | Storage | src/storage/ | 16 | Stored data: save and load paths | reviewed | __BASE__ |
| 2 | Status line and list | src/ui/ | 12 | Boundary: what the user is told after a save | reviewed | __BASE__ |
| 3 | Export | src/export/ | 4 | Boundary: data leaves the app as a file | reviewed | __BASE__ |
| 4 | Text helpers | src/util/ | 4 | Everything else | reviewed | __BASE__ |

No secret files in the history.

## Findings
1. **Critical** · `src/storage/entries.js:10` · a failed save is reported as saved · area 1
   Scenario: storage full → `setItem` throws → the catch logs at debug level and the function still returns true → `onSave` shows "Saved" and the entry is lost on reload.
   Verified: traced
   Fix (not applied): return false from the catch so the status line shows its own failure message.
   Status: decided for branch 1
2. **Important** · `src/export/csv.js:2` · a comma in an entry's text splits it into two columns · area 3
   Scenario: an entry "milk, eggs" → `toCsv` joins fields with commas and no quoting → the CSV row has three columns and a spreadsheet shows "eggs" as a separate field.
   Verified: traced
   Fix (not applied): quote fields that hold a comma, a quote or a line break.
   Status: deferred — the export is due for a rewrite with its own spec
3. **Minor** · `src/util/text.js:3` · a cut text is one character longer than max · area 4
   Scenario: a 50-character entry → `shorten(text, 40)` keeps 40 characters and adds the ellipsis → 41 characters overflow the 40-character column.
   Verified: traced
   Fix (not applied): keep max - 1 characters before the ellipsis.
   Status: decided for branch 1

## Possible
- `src/storage/entries.js:5` · `JSON.parse` on a damaged value would throw on load; no caller in the project catches it, but nothing writes a damaged value either.

## Contracts to check
- ~~1 produces the boolean from `saveEntries` that 2 consumes in `onSave`~~ checked in area 2: holds except when the save fails, joined to finding 1

## Already known
- none

## Looked at and found sound
- 2: the status line has both messages wired; `renderEntries` keeps one entry per line.

## Recommended order
1. `fix/save-and-shorten` · findings 1 and 3 · `src/storage/entries.js`, `src/util/text.js`
2. the CSV export, deferred to its rewrite (finding 2)
EOF
sed -i "s/__BASE__/$BASE/g" .review/report.md
cp .review/report.md .git/fixture-report-copy.md
