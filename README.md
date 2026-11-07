# code-care-skills

`code-cleanup`, `branch-cleanup`, `project-review` and `branch-review`: four guided, safe skills for [Claude Code](https://claude.com/claude-code), written for people who can follow commands but would rather not diagnose a broken build. Two of them clean; two review. They share the same safety rules and differ in scope and in what they are allowed to touch.

## Which one to use

| | `code-cleanup` | `branch-cleanup` | `project-review` | `branch-review` |
|---|---|---|---|---|
| Scope | A whole project or one folder | Only what one branch adds, plus whatever that diff left orphaned in older code | A whole project or one folder, one area per pass | Only what one branch adds |
| Where it works | A new cleanup branch cut from yours | The branch under review, with the cleanup commits on top | Wherever you are, read only: no edit, no commit | The branch under review, read only: no edit, no commit |
| Use it when | Tidying a codebase, removing dead code, getting a repo ready to launch or show | Polishing a feature or delivery before opening or merging its pull request | Hunting real defects in an existing codebase | Hunting real defects in a feature or delivery before opening or merging its pull request |
| Rest of the codebase | Fair game | Out of bounds: seen-but-not-touched lines go in the summary | All of it, ranked by risk, with the areas not yet reviewed named as such | Out of bounds: one line under "Seen outside the scope", or nothing |
| Report | `.cleanup/report.md` with a plan, a baseline and a before-and-after table | A `## Cleanup` section to paste into the pull request description | Findings with file, line, scenario and severity, a coverage line, and fix branches in order; kept in `.review/report.md` if you agree | A list of findings with file, line and failure scenario, plus a `## Review` section for the pull request |
| Starting point | Baseline of every check, saved to a file | Asks whether the checks passed at HEAD; runs them once if not | A map of the project's areas, ranked by risk | Nothing to run: it reads the diff and the code around it |

If you are unsure, two questions decide it. Do you want to find what is wrong, or tidy what is untidy? The first is a review, the second a cleanup. And is it about the whole project or one branch? When you want both a review and a cleanup, review first: the fixes are new code the cleanup should see. Each skill's description points at the others, so Claude picks the right one from how you phrase the request.

## code-cleanup in short

Asking an agent to "clean up the code" usually ends in one large diff that mixes deleted dead code with renamed variables, reformatted files and a quietly fixed bug. If something breaks, there is no telling which change did it. This skill does the opposite: it works on a separate branch, measures the project before touching anything, sorts every finding by risk, and applies the changes in small blocks, one commit each, that you approve one at a time. Anything that would change behaviour goes into a report instead of into the code.

```
Plan: 6 blocks
1. Remove unused imports in src/                 level 1
2. Remove repeated keys in the i18n dictionary   level 1
3. Remove debug logs left in the importer        level 2
4. Remove CSS selectors that match nothing       level 2   (visual check)
5. Merge two copies of the date formatter        level 2   (reviewed)
6. Format with the project's Prettier config     level 2   (last)

Level 3, report only: 2 bugs (1 important), 1 tracked .env, 1 data migration
Apply block 1?
```

## What is in the box

| Path | What it is |
|---|---|
| `code-cleanup/SKILL.md` | The skill: safety net, baseline, inventory, analysis in three levels, block-by-block application, wrap-up |
| `code-cleanup/references/worktree.md` | Working in a git worktree: what it costs, how to create it, how to remove it without losing anything. Read only when a worktree is on the table |
| `code-cleanup/references/find-skills.md` | Searching the open skills registry for extra help, with permission before anything is downloaded. Read only if you ask for it |
| `code-cleanup/references/report-template.md` | The structure of the final report |
| `code-cleanup/scripts/skill-inventory.mjs` | Lists installed skills, subagents and plugins (marking disabled ones) and plugins available in your marketplaces, filtered and ranked by keyword. Read-only |
| `code-cleanup/evals/` | Three test cases: stops in a folder without git, keeps what only looks unused while removing what is, leaves migrations, bugs and an old `.env` to the report |
| `branch-cleanup/SKILL.md` | The skill: fix the scope from the branch's diff, know the checks, plan blocks, apply block by block, wrap up with a pull request section |
| `branch-cleanup/evals/` | Three test cases, each with a script that builds a throwaway repository, a prompt and graders: stays inside the fence, stops on a dirty tree, finds an orphan built from text |
| `project-review/SKILL.md` | The skill: map the project into areas, rank them by risk (stored data first), review one area per pass with the two lenses, verify every candidate, record coverage per area and commit, close with fix branches in order |
| `project-review/references/report-template.md` | The structure of `.review/report.md` |
| `project-review/references/web-stack.md` | A copy of `branch-review`'s stack reference: each skill installs on its own, so each carries its own copy |
| `project-review/evals/` | Four test cases: finds a migration that writes an empty library over the user's data and an old `.env` in the history, skips defects the project already records, reviews only the riskiest area and stays read-only when asked to fix, resumes a review after a fix landed |
| `tools/check-copies.mjs` | Checks that the files two skills share have not drifted apart: `node tools/check-copies.mjs` |
| `branch-review/SKILL.md` | The skill: fix the scope from the branch's diff, read enough to judge, two lenses (silent failures, type design), verify every candidate, report with severities and a pull request section |
| `branch-review/references/web-stack.md` | Failure patterns and checks for React, TypeScript, ProseMirror, Dexie, Vitest and Playwright, read only when `package.json` names one of them |
| `branch-review/evals/` | Three test cases: finds a swallowed error and a colliding id while leaving old code alone, ignores decoys that look like defects, stays read-only when asked to fix on the spot |

## Install

Copy the skill folders you want into your skills directory:

```bash
cp -r code-cleanup ~/.claude/skills/code-cleanup
cp -r branch-cleanup ~/.claude/skills/branch-cleanup
cp -r project-review ~/.claude/skills/project-review
cp -r branch-review ~/.claude/skills/branch-review
```

Then ask Claude to clean up a project or a folder (or run `/code-cleanup`), to tidy the branch before a pull request (or run `/branch-cleanup`), to look for bugs in the whole project (or run `/project-review`), or to look for bugs in the branch before the pull request (or run `/branch-review`). The inventory script of `code-cleanup` needs Node.js; without it the skill falls back to looking at the skill folders by hand. The other three need nothing but git, and `project-review` works without it too, with no history to rank by. None of the `evals/` folders are needed to use the skills.

## How code-cleanup works

**Phase 0, safety net.** Checks the folder is a git repository (and offers to create one, with a `.gitignore` first so secrets and `node_modules` stay out), refuses to mix your uncommitted work into the cleanup, and creates a cleanup branch. Optionally it works in a git worktree, so you can keep working in your own folder meanwhile. The report lives in a `.cleanup/` folder excluded through `.git/info/exclude`, so it never reaches a commit.

**Phase 1, baseline.** Finds the project's real checks, in its scripts and its CI configuration, and splits them into fast (unit tests, lint, types, build) and slow (end-to-end tests). Runs all of them once and records what already failed, so an old failure is never blamed on the cleanup. Warns about a development server left running, which end-to-end tests can silently test instead of the branch.

**Phase 2, inventory.** Uses the skills you already have (`/simplify`, `/code-review`, a `code-simplifier` subagent...) rather than imitating them. **Phase 3**, searching for new ones, is optional and asks before downloading anything.

**Phase 4, analysis.** Every finding gets a level:

- **Level 1, safe and mechanical:** unused imports and variables, repeated keys in an object literal. Imports with side effects, re-exports and variables holding a call are deliberately excluded.
- **Level 2, needs judgement:** duplicate or long functions, files and dependencies that look unused, logs, commented-out code, dead CSS, unused i18n keys, outdated comments and docs, dead config options, formatting with the project's own formatter.
- **Level 3, report only:** behaviour changes, bugs, anything touching authentication, payments or stored data (including data migrations written as code, such as Dexie's `db.version(n).upgrade(...)`), public exports, dependency upgrades, secrets. Each finding gets a severity (critical, important or minor, the same three levels the branch skills use), a fix risk, a size and how it was checked; a bug also needs a failure scenario and a look for the guard that would stop it, the standard `branch-review` uses. The report ends with a recommended order of separate pieces of work.

Before calling anything unused, the skill looks for indirect references, above all names built from strings: `"nav" + id` uses a class called `navchallenges` that appears nowhere in the code. It also knows the references frameworks add on their own: pytest fixtures, decorators, `import React` under the classic JSX runtime, component templates, entry points named in configuration, and files reached only by URL such as `public/` or a service worker.

**Phase 5, block by block.** Explain, ask, apply, check, commit. Fast checks run on every block; slow ones only on blocks that change something visible, and all of them at the end. Blocks that change how things look need a visual comparison. Only logic blocks go through a review subagent. A failing block is undone and noted, not patched on the spot. Pre-commit hooks are never skipped.

**Phase 6, wrap-up.** Runs everything once more, fills in the report with before-and-after measurements, and explains how to review, keep or discard the branch. It never merges or pushes: that is your call. If a slow check fails only at the end, one commit per block means `git bisect` can find the culprit. If `branch-review` is installed, it offers a read-only review of the cleanup branch against your starting branch, just before the formatting block when there is one, so the formatter's lines stay out of it: a cleanup should change no behaviour, so any finding points at a block to revert.

Its `evals/` folder holds three cases. One runs it in a folder that is not a git repository and holds a `.env` and `node_modules/`, and checks that it stops, offers git with a `.gitignore` first, and creates nothing. One plants a side-effect import, a call assigned to an unused variable and translation keys built from text next to a really unused import and a repeated key, with tests that cover none of the traps, and checks that only the real ones go. One plants data migrations that invite a refactor, a pagination bug the tests miss and a `.env` deleted from the tree but still in the history, and checks that all three end in the report and none in the code.

## How branch-cleanup works

**Scope is a fence.** The scope is the branch's own diff, measured from the merge base so later commits on the base do not leak in, plus the orphans: code outside the diff that the diff made dead or untrue, such as a CSS class, keyframes, a function or a translation key whose last user the branch removed, and comments beside changed code that now describe something gone. It finds them by searching for every name the branch deleted, including names built from text. Anything else, even older code next to a change, is mentioned in one line under "Seen outside the scope" and left alone.

**Same branch, no baseline folder.** It starts only from a clean tree on a branch that is not the default one, notes the starting commit and commits each block on top of the branch. It does not create a cleanup branch or a `.cleanup/` folder; the commits themselves keep the progress.

**Same levels, smaller plan.** Findings are sorted into the three levels used by `code-cleanup` (mechanical, needs judgement, report only). A branch usually yields two to six blocks, and more than about eight means the branch is too big for one pass. The tooling is sized to the diff: up to about 150 changed lines it reads the hunks itself, above that it can use `/simplify`, and `/code-review` is reserved for blocks that change logic.

**Wrap-up.** It runs all the checks, compares the lines the branch adds before and after, and writes a `## Cleanup` section (applied, skipped, left for later, seen outside the scope) to paste into the pull request description. Reviewing the commits, opening the pull request and merging stay with you.

The `evals/` folder holds the cases used to test it. Each builds a small repository with deliberately untidy old code on `main` and a feature branch on top, then grades whether the skill cleaned the branch, left the old code exactly as it was, and made one commit per block without merging, pushing or stashing.

## How branch-review works

**Same fence, no hands.** The scope is the branch's own diff from the merge base, the same as `branch-cleanup`. The difference is that this skill changes nothing: its tools are limited to reading files and running `git` queries, it does not run the tests, and when the user asks it to fix what it found it says that fixing is a separate task and stops. Uncommitted changes do not block it, but they are not reviewed either, and the report says so.

**Two lenses.** *Silent failures*: errors swallowed into a default, fallbacks that hide what happened, screens that look alive after the thing behind them died, work that never completes on the failure path, cancellation mistaken for failure, and wrong results that raise no exception at all (progress saved under the wrong key, two copies of one rule drifting apart). *Type design*: ids that can collide or that are not stable, one value with two meanings, state spread over fields that must agree, trust boundaries without a check, invariants the code relies on but nothing enforces.

**Verify before reporting.** Every candidate needs a written scenario (trigger, path, result) and a look for the guard that would stop it. No scenario means no finding. Missing tests, style, naming and design preferences without a defect behind them are dropped on purpose, and so are conventions the reviewer brings from elsewhere: the project's `CLAUDE.md` decides how it logs and names things. Each finding says how it was verified (`traced`, `read` or `would need running`) and gets one of three severities with a stated test for each.

**Report.** Findings, then "Possible", "Already known", "Seen outside the scope" and "Looked at and found sound", in the chat; then a `## Review` section to paste into the pull request description. Deciding what to fix, and fixing it, stays with you.

Its `evals/` folder holds three cases. One plants a swallowed parse error and a colliding id on a branch next to an old swallowed error on `main`, and checks that the branch defects are reported with scenarios and the old one is not. One plants a real defect among decoys (a catch that rethrows, a field read through a list of names, a style the project asked for) and checks that only the defect is reported. One asks the skill to fix what it finds, with an uncommitted change in the tree, and checks that nothing but that change is in the tree afterwards.

## How project-review works

**A map before a pass.** A diff can be read whole; a project cannot. So the skill first groups the files into areas by role (data layer, boundaries, flows, utilities), then ranks them: stored data and migrations first, because a mistake there costs someone their data; then the places where outside input comes in or operations can fail; then the files that change most or that fixes keep landing on; and areas no test or CI job exercises move up. It also lists every secret file ever added to the history, without opening any.

**One area per pass, with the same standard as `branch-review`.** The two lenses, a written scenario for every finding, a look for the guard, one finding per root cause, three severities. What a project-wide review adds is the contract between areas: one area produces a value another consumes, and they disagree. What the project already records, in `CLAUDE.md`, a TODO list or the "Pending" of a `code-cleanup` report, is listed as already known rather than reported again.

**Coverage is part of the report.** Every area is marked reviewed at a given commit, skipped or not reached, so a short list of findings over three areas of twelve reads as exactly that. When you come back in a new session, areas that changed since their pass are marked stale and go back into the ranking.

**Read only, except its own report.** It edits nothing, commits nothing and runs neither the tests nor the app. The report goes in `.review/report.md`, excluded from git through `.git/info/exclude`, only if you agree; `allowed-tools` leaves out the write tools so that both writes ask for permission. It closes with the findings grouped into fix branches in order, each to be checked with `branch-review` before merging, and `code-cleanup` once the fixes are in.

Its `evals/` folder holds four cases. One plants a migration that crashes on old notes without tags inside a loader that swallows the error and saves an empty library over the data, an old `.env` in the history, and untidy but harmless code, and checks that the data loss and the secret are reported and the untidiness is not. One plants two defects the project already records (in `CLAUDE.md` and in a cleanup report) and one it does not, a store that returns `undefined` where its caller checks for `null`, and checks that only the new one is reported. One asks for the riskiest area only and for a fix on the spot, and checks that the storage area is chosen, the other areas are named as not reviewed, and nothing is edited. One resumes from an earlier report after a fix for its finding was merged, and checks that the changed area is marked stale and the unchanged one kept, the finding is treated as fixed and still to be confirmed, the plan and its cost are given again before any new area is read, and nothing is written before the go-ahead.

## Rules they do not bend

A project's `CLAUDE.md` governs conventions such as branch names, commit language and how tests are run. It cannot lower the safety rules: no `merge`, `push`, `rebase`, `reset --hard` or `stash`, no behaviour change, no `--no-verify`, nothing downloaded and run without asking, no AI signatures in commits. `code-cleanup` also never touches your starting branch, since all its work happens on a new one; `branch-cleanup` works on the branch under review and never leaves it; `branch-review` edits nothing at all, and `project-review` writes only its own report, after asking.

## Large projects

With `code-cleanup`, on a project with more than about eight blocks, the skill proposes writing the plan, closing the session, and applying a few blocks per new session from the report. Every message resends the whole conversation, so several short sessions cost much less than one long one. Test output is written to a log file and only its summary is read, for the same reason. `project-review` does the same with areas: two to four per session, with the report carrying the map from one session to the next.

## Costs

The cost depends mostly on the size of the project or diff, the number of blocks and how long the test output is. `code-cleanup` itself is about 8.5k tokens and the files under its `references/` load only when needed. `branch-cleanup` is a single file of about 3.5k tokens and has not been measured yet.

`code-cleanup` was measured on its three eval cases on 2026-11-06, one run each with and without the skill on the same model, on projects of 20 to 50 lines: about 118k tokens and 3 minutes per run with the skill against 96k and under 2 minutes without, so the skill costs about 23 percent more on a small project, most of it in the work it adds (the inventory, the baseline and the report). With the skill every criterion passed (17 of 17); without it, 71 percent. The model avoided the traps of level 1 and left the migrations alone either way. What only the skill did: propose a `.gitignore` before the first commit in a folder without git, flag a `.env` deleted from the tree but still in the history, give every bug a severity and say how it was checked, and keep the report in `.cleanup/` out of git. The baseline ran with a `CLAUDE.md` that already asks for care before writing, so on a plain setup the gap is likely wider. Run again with the skill on 2026-11-08, after the changes in v1.1.0: 17 of 17 once more, about 117k tokens per run. Re-measure on a real project before trusting these figures for one.

`branch-review` was measured on its three eval cases, diffs of 25 to 51 lines, one run each with and without the skill on the same model: about 104k tokens and 97 seconds per review with the skill against 98k and 91 seconds without, so the skill itself costs about 6 percent on a small diff. Without it the model found the same planted defects but rated only some of them, listed missing tests as findings, and, when asked to fix on the spot, edited the repository; with it, every finding carried a severity and a scenario and nothing was edited. The skill is about 4k tokens and `references/web-stack.md` another 2k when it applies.

`project-review` was measured on its three eval cases on 2026-11-06, projects of 20 to 50 lines, one run each with and without the skill on the same model: about 104k tokens and 100 seconds per run with the skill against 94k and 72 seconds without, about 11 percent more. With the skill every criterion passed (16 of 16); without it, 10 of 16. The model found every planted defect either way. What only the skill did: flag the `.env` still in the history (without it the model said there were no secrets), keep cleanup items and missing tests out of the findings, give every finding a severity and say how it was checked, and, asked to fix on the spot, stay read only and hand back a fix branch instead of editing the code. The fixtures are small enough to cover in one pass, so the map and the ranking were barely tested; re-measure on a real project before trusting these figures for one. The skill is about 4k tokens.

## Licence

MIT. See `LICENSE`.
