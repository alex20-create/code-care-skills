#!/usr/bin/env bash
# Builds the test repository in the current folder: main with a scene model,
# feat/export adding a Fountain exporter that silently drops scenes without a
# heading, and one uncommitted edit in README.md left in the working tree.
set -eu
git init -q -b main .
git config user.name "Fixture"
git config user.email "fixture@example.com"
git config core.autocrlf false

cat > package.json <<'EOF'
{
  "name": "export-fixture",
  "private": true,
  "type": "module",
  "scripts": { "test": "node test.mjs" }
}
EOF

cat > CLAUDE.md <<'EOF'
# CLAUDE.md

- Local-first screenplay editor. A script is an ordered list of scenes; each scene has a heading (place, location, time) and typed blocks.
- Checks: `npm test` (fast). No end-to-end tests, no dev server.
- Commits: Conventional Commits, imperative, lowercase, English. Pull requests in English.
EOF

cat > README.md <<'EOF'
# Export fixture

Scenes and blocks, exported to Fountain.
EOF

mkdir -p src

cat > src/scenes.mjs <<'EOF'
export const scene = (heading, blocks) => ({ heading, blocks });

export const action = (text) => ({ type: "action", text });
export const character = (name) => ({ type: "character", text: name });
export const dialogue = (text) => ({ type: "dialogue", text });
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { scene, action } from "./src/scenes.mjs";

const s = scene("INT. KITCHEN - NIGHT", [action("The kettle boils.")]);
assert.equal(s.blocks.length, 1);
console.log("ok");
EOF

git add -A
git commit -q -m "feat: scene model"

git switch -q -c feat/export

cat > src/export.mjs <<'EOF'
const line = (block) => {
  if (block.type === "character") return block.text.toUpperCase();
  return block.text;
};

export const exportFountain = (scenes) => {
  const out = [];
  for (const s of scenes) {
    if (!s.heading) continue;
    out.push(s.heading.toUpperCase(), "");
    for (const block of s.blocks) out.push(line(block), "");
  }
  return out.join("\n").trimEnd() + "\n";
};
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { scene, action, character, dialogue } from "./src/scenes.mjs";
import { exportFountain } from "./src/export.mjs";

const s = scene("INT. KITCHEN - NIGHT", [action("The kettle boils."), character("Ana"), dialogue("Tea?")]);
assert.equal(s.blocks.length, 3);

const text = exportFountain([s]);
assert.ok(text.startsWith("INT. KITCHEN - NIGHT\n"));
assert.ok(text.includes("\nANA\n"));
console.log("ok");
EOF

git add -A
git commit -q -m "feat: export the script to fountain"

cat >> README.md <<'EOF'

- WIP: notes on the export format, not ready to commit.
EOF
