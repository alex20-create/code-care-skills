#!/usr/bin/env node
// Each skill installs by copying its own folder, so a reference two skills
// share lives in both. This checks that the copies have not drifted apart.
// Run from the repository root: node tools/check-copies.mjs
import { readFileSync } from "node:fs";

const SHARED = [
  ["branch-review/references/web-stack.md", "project-review/references/web-stack.md"],
];

const read = (path) => readFileSync(path, "utf8").replace(/\r\n/g, "\n");

let drifted = 0;
for (const [first, ...others] of SHARED) {
  const text = read(first);
  for (const other of others) {
    if (read(other) !== text) {
      console.error(`Drifted: ${other} differs from ${first}`);
      drifted++;
    }
  }
}
if (drifted) process.exit(1);
console.log(`ok: ${SHARED.length} shared file(s) identical`);
