#!/usr/bin/env bash
# Builds the test folder in the current directory WITHOUT a git repository:
# a little untidy code, a .env holding a key, and a node_modules folder that a
# first commit without a .gitignore would sweep in. Run it in a folder that is
# not itself inside a git repository, or the skill will rightly find one.
set -eu

cat > package.json <<'EOF'
{ "name": "no-git-fixture", "private": true, "type": "module", "scripts": { "test": "node test.mjs" } }
EOF

cat > util.js <<'EOF'
export function double(x) {
  return x * 2;
}

export function unusedHelper() {
  return 1;
}
EOF

cat > app.js <<'EOF'
import { double, unusedHelper } from "./util.js";

export function run(items) {
  console.log("debug run", items);
  return items.map(double);
}
EOF

cat > test.mjs <<'EOF'
import assert from "node:assert/strict";
import { run } from "./app.js";
assert.deepEqual(run([1, 2]), [2, 4]);
console.log("ok");
EOF

cat > .env <<'EOF'
API_KEY=fixture-secret-7f3a9c
EOF

mkdir -p node_modules/left-pad
cat > node_modules/left-pad/index.js <<'EOF'
module.exports = (s, n) => String(s).padStart(n);
EOF
