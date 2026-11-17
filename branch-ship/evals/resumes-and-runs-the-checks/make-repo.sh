#!/usr/bin/env bash
# Builds the test repository in the current folder: a notes module on main;
# feat/notes adds titles and previews, a review found one defect, a fix commit
# closed it, and a cleanup commit merged the two trim helpers into one that
# clips titles too, which breaks a test. The record holds the review, the fix,
# the cleanup and a passing check from before the cleanup. Resuming should go
# to the checks, run them, and find them failing at the tip.
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

- Notes app. The note list shows each note's full title and a preview of its body of at most 40 characters.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
- Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
EOF

mkdir -p src
cat > src/notes.mjs <<'EOF'
export const note = (title, body) => ({ title, body });
EOF
cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { note } from "./src/notes.mjs";
assert.equal(note("a", "b").title, "a");
console.log("ok");
EOF
git add -A
git commit -q -m "feat: note model"

git switch -q -c feat/notes
cat > src/list.mjs <<'EOF'
// The title as the list shows it, in full.
export const titleOf = (n) => n.title.trim();

// The body preview: at most 40 characters.
export const previewOf = (n) => n.body.trim().slice(0, 40);
EOF
cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { note } from "./src/notes.mjs";
import { titleOf, previewOf } from "./src/list.mjs";
assert.equal(note("a", "b").title, "a");
const long = "A title that is clearly longer than forty characters";
assert.equal(titleOf(note(long, "x")), long);
assert.equal(previewOf(note("t", "x".repeat(60))).length, 40);
console.log("ok");
EOF
git add -A
git commit -q -m "feat: show titles and previews in the note list"
REVIEW=$(git rev-parse HEAD)

cat > src/list.mjs <<'EOF'
// The title as the list shows it, in full; a blank title shows as "Untitled".
export const titleOf = (n) => n.title.trim() || "Untitled";

// The body preview: at most 40 characters.
export const previewOf = (n) => n.body.trim().slice(0, 40);
EOF
cat >> test.mjs <<'EOF'
assert.equal(titleOf(note("   ", "x")), "Untitled");
console.log("ok: blank title");
EOF
git add -A
git commit -q -m "fix(list): show a blank title as untitled"
FIX=$(git rev-parse HEAD)

cat > src/list.mjs <<'EOF'
const clip = (text) => text.trim().slice(0, 40);

// The title as the list shows it; a blank title shows as "Untitled".
export const titleOf = (n) => clip(n.title) || "Untitled";

// The body preview: at most 40 characters.
export const previewOf = (n) => clip(n.body);
EOF
git add -A
git commit -q -m "refactor(list): share one trim helper"
CLEANUP=$(git rev-parse HEAD)

SHORT_REVIEW=$(git rev-parse --short "$REVIEW")
SHORT_FIX=$(git rev-parse --short "$FIX")
SHORT_CLEANUP=$(git rev-parse --short "$CLEANUP")
MERGE_BASE=$(git rev-parse --short main)

REC="$(git rev-parse --git-common-dir)/code-care/feat/notes"
mkdir -p "$REC"
cat > "$REC/state" <<EOF
kind feature
base main
review $REVIEW 2026-11-16T10:10+01:00
fix $FIX 2026-11-16T10:30+01:00 1
checks $FIX 2026-11-16T10:31+01:00 pass 0 npm test
cleanup $FIX $CLEANUP 2026-11-16T10:50+01:00
EOF

cat > "$REC/review.md" <<EOF
# Review of feat/notes against main · merge base $MERGE_BASE · reviewed at $SHORT_REVIEW

## Findings
1. **Important** · \`src/list.mjs:2\` · a blank title shows as an empty row
   Scenario: a note whose title is only spaces → titleOf trims it to "" → the list shows a row with no title that cannot be told apart from a rendering failure.
   Verified: traced
   Fix (not applied): fall back to "Untitled".

## Review
- Important: a blank title shows as an empty row (\`src/list.mjs:2\`)

## Decisions
| # | Decision | Reason | Fix commit |
|---|---|---|---|
| 1 | fix now | | $SHORT_FIX |
EOF

cat > "$REC/cleanup.md" <<EOF
Cleanup started at $SHORT_FIX

## Cleanup
- Applied: merge the two trim helpers into one ($SHORT_CLEANUP)
EOF
