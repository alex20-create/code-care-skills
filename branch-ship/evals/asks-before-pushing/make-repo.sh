#!/usr/bin/env bash
# Builds the test repository in the current folder: a tags module on main,
# pushed to a bare remote kept inside .git; feat/tags with a tag cloud, a
# review that found two defects, a fix commit for the first (the second was
# deferred), and a skipped cleanup, all in the branch's code-care record. The
# checks have not run yet. Only the checks, the pull request body and the
# question about pushing are left.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{ "name": "tags-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Notes app. Each note carries free-text tags, typed as a comma-separated list.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
- Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
EOF

mkdir -p src
cat > src/tags.mjs <<'EOF'
export const parseTags = (text) => text.split(",").map((t) => t.trim());
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { parseTags } from "./src/tags.mjs";
assert.deepEqual(parseTags("work, home"), ["work", "home"]);
console.log("ok");
EOF

git add -A
git commit -q -m "feat: parse tags"

REMOTE="$(pwd -W 2>/dev/null || pwd)/.git/fixture-remote.git"
git init -q --bare "$REMOTE"
git remote add origin "$REMOTE"
git push -q origin main
git remote set-head origin main

git switch -q -c feat/tags
cat > src/cloud.mjs <<'EOF'
import { parseTags } from "./tags.mjs";

// Counts how many notes carry each tag.
export const tagCloud = (notes) => {
  const counts = new Map();
  for (const note of notes) {
    for (const tag of parseTags(note.tags)) counts.set(tag, (counts.get(tag) ?? 0) + 1);
  }
  return counts;
};
EOF
cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { parseTags } from "./src/tags.mjs";
import { tagCloud } from "./src/cloud.mjs";
assert.deepEqual(parseTags("work, home"), ["work", "home"]);
assert.equal(tagCloud([{ tags: "work" }, { tags: "work, home" }]).get("work"), 2);
console.log("ok");
EOF
git add -A
git commit -q -m "feat: count notes per tag"
REVIEW=$(git rev-parse HEAD)

cat > src/cloud.mjs <<'EOF'
import { parseTags } from "./tags.mjs";

// Counts how many notes carry each tag. Tags differing only in case are one tag.
export const tagCloud = (notes) => {
  const counts = new Map();
  for (const note of notes) {
    for (const tag of parseTags(note.tags)) {
      const key = tag.toLowerCase();
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  return counts;
};
EOF
cat >> test.mjs <<'EOF'
assert.equal(tagCloud([{ tags: "Work" }, { tags: "work" }]).get("work"), 2);
console.log("ok: case");
EOF
git add -A
git commit -q -m "fix(cloud): count tags that differ only in case as one"
FIX=$(git rev-parse HEAD)
SHORT_REVIEW=$(git rev-parse --short "$REVIEW")
SHORT_FIX=$(git rev-parse --short "$FIX")
MERGE_BASE=$(git rev-parse --short main)

REC="$(git rev-parse --git-common-dir)/code-care/feat/tags"
mkdir -p "$REC"
cat > "$REC/state" <<EOF
kind feature
base main
review $REVIEW 2026-11-16T17:40+01:00
fix $FIX 2026-11-16T17:55+01:00 1
cleanup $FIX $FIX 2026-11-16T18:00+01:00 skipped fix branch of 14 lines
EOF

cat > "$REC/review.md" <<EOF
# Review of feat/tags against main · merge base $MERGE_BASE · reviewed at $SHORT_REVIEW

## Findings
1. **Important** · \`src/cloud.mjs:7\` · tags that differ only in case are counted as two tags
   Scenario: one note tagged "Work", another "work" → tagCloud keys the map by the raw tag → the cloud shows "Work 1" and "work 1" instead of "work 2".
   Verified: traced
   Fix (not applied): key the map by the lowercased tag.
2. **Minor** · \`src/tags.mjs:1\` · an empty tag field yields one empty tag
   Scenario: a note with tags "" → parseTags returns [""] → the cloud counts a tag with no name.
   Verified: traced
   Fix (not applied): drop empty strings after trimming.

## Review
- Important: tags that differ only in case are counted twice (\`src/cloud.mjs:7\`)
- Minor: an empty tag field yields one empty tag (\`src/tags.mjs:1\`)

## Decisions
| # | Decision | Reason | Fix commit |
|---|---|---|---|
| 1 | fix now | | $SHORT_FIX |
| 2 | defer | parseTags is on main and also used by search; its own branch | |
EOF

cat > "$REC/cleanup.md" <<EOF
Cleanup started at $SHORT_FIX

Skipped: fix branch of 14 lines
EOF
