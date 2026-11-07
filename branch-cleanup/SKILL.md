---
name: branch-cleanup
description: Guided, safe cleanup of only what one branch adds — a feature, a delivery, a PR in the making — before it is merged. Its scope is the branch's own diff plus whatever that diff left orphaned in older code, and nothing else. Works on the same branch, applies changes in blocks the user approves one at a time, checks after each block and commits each one separately. Use it whenever the user wants to tidy, simplify or polish the work of the current branch, delivery or pull request before merging or opening it, especially when they do not want the rest of the codebase touched — "clean up what we just built", "tidy this branch before the PR", "simplify the new code", and in Spanish "repasa lo de esta entrega", "limpia la rama antes del PR", "deja limpio lo nuevo". For a whole project or folder use code-cleanup instead; when the branch should also be checked for bugs, branch-review runs first; for one function, just edit it.
---

# Branch cleanup

The goal is to leave what **this branch adds** cleaner, without changing what it does and without touching anything the branch did not touch or leave orphaned. The rest of the project is out of bounds: the user has cleaned it already, or wants this branch's pull request to stay small enough to review and to revert on its own.

Whoever uses this skill may not be a seasoned programmer: they can follow commands but not diagnose a failure. So safety (one commit per block, checking after every change) comes before speed, and every step is explained in plain language: what is about to happen, why, and how to undo it.

Speak the user's language.

## Rules that do not bend

A mistake here can cost the user real work, which is why these hold even when something else seems to suggest otherwise:

- **The project's and the user's `CLAUDE.md` govern conventions**: commit style, language, how to run the checks, asking before writing. Follow them. What they never do is lower the rules in this list. If one clashes with them, stop and ask.
- **Stay on the branch under review.** Blocks are committed on top of it. Never `merge`, `push`, `rebase`, `reset --hard`, `push --force`, `stash` or delete branches: merging and opening the pull request are the user's call.
- **The scope is a fence.** A line outside the scope is not changed, however obviously it could be improved. Mention it in one line under "Seen outside the scope" in the summary, or not at all if it is trivial. Touching it would mix old code into a pull request that is meant to be about the new, and would reopen work the user considers finished.
- **Do not change behaviour.** Cleaning is not adding features or fixing logic. A bug goes into the summary, not into a block.
- **Never skip hooks.** A failing pre-commit hook is a failure of the block (step 4).
- **No AI signatures.** No `Co-Authored-By`, "Generated with…" or any mention of AI in commits, comments or descriptions.
- **Secrets:** do not read out or copy keys, tokens or passwords. Flag them as critical in the summary, saying where they are (file, or commit and path) but never the value, and leave them alone. A failure scenario and how it was checked do not apply to a secret: write "n/a".
- **Do not hand-edit** `.env*`, credentials, lock files or data migrations, including migrations that live as code inside another file (a list of steps run when stored data is loaded, `db.version(n).upgrade(...)`). Changing them changes what happens to data the user already has.
- **Nothing that downloads and runs code without permission** (`npx`, `pipx`, `uvx` and the like): name the package and wait for a yes.

Where a step below says to ask something the user has already answered in the conversation (whether the checks passed, whether a development server is open, approval for a level), use that answer instead of asking again.

## 1. Fix the scope

1. `git branch --show-current`. If it is the default branch, or empty (detached HEAD), stop and explain: there is no branch to review. Ask which one they mean.
2. Find the base, the branch this one will merge into. Use the one the user names, else what `CLAUDE.md` says, else `git symbolic-ref --short refs/remotes/origin/HEAD`, else `main` or `master`, whichever exists. If in doubt, ask. Then `git merge-base <base> HEAD`: everything is measured from that commit, so later commits on the base do not leak into the scope.
3. `git status --porcelain` must be empty. If not, stop and ask: commit their pending work on this branch first (with their approval), or cancel. Never `stash`: it is easy to forget what was put aside, and their pending work must not mix with the cleanup.
4. Note the cleanup's starting point: `git rev-parse --short HEAD`. Every block committed from here on is listed by `git log <start>..HEAD`, which is how a later session finds where the work stopped.
5. Read the diff: `git diff --stat <merge-base>...HEAD`, then the hunks themselves. Do not read whole files, only the hunks and the lines around them. In a long file, reading it whole costs a lot and adds nothing. **The scope is two things:**
   - **The changed lines**: the hunks the branch adds or modifies.
   - **The orphans**: code outside the diff that the diff made dead or untrue. That means definitions whose last user the branch removed or replaced (a CSS class, a set of keyframes, a CSS variable, a function, a translation key, a test helper), and comments or docs beside changed code that now describe something that no longer exists. To find them, take every name the branch deleted or replaced (lines starting with `-` in the diff) and search the codebase for what still refers to it (`rg`, `git grep`). Include names built from text: `"nav" + id` uses the class `navchallenges` even though that word is written nowhere. A definition is an orphan only when nothing refers to it any more. If that cannot be proved, it is not an orphan: it goes into the summary as level 3.
   - Nothing else is in scope, not even older code in the same file right next to a change.
6. Tell the user in two or three sentences: the branch, the base, how many files and lines the diff has (the `--stat` total; orphans are listed apart, since they are not counted there), and that every block will be its own commit, so any of them can be undone with `git revert <commit>`.
7. If the diff runs to thousands of lines, propose reviewing it file by file, across more than one session if needed.
8. If the user also wants the branch checked for defects, that is `branch-review`, and it goes first: its findings turn into fixes, and fixes are new code that this cleanup should see. Mention it in one line and let them choose.

## 2. Know the checks

Find the project's real checks (in `CLAUDE.md`, the `scripts` of `package.json` or their equivalent, and the CI configuration such as `.github/workflows/*.yml`, which shows what the project actually relies on). If the CI runs on systems or versions this machine does not have, say so in the summary as something not checked here. Split the checks in two:

- **Fast** (seconds): lint, types, unit tests, build. They run after every block.
- **Slow** (minutes): mostly end-to-end tests. They run on blocks that change something visible, and once at the end.

The branch's own work has usually just run them. Ask whether they all passed at the current HEAD. If the user is sure, that is the starting point. If not, run them once now, the slow ones included, so a failure that was already there is not blamed on a block. Redirect each check's output to a file in a temporary folder outside the repository (the session's scratch folder if it has one, else the system's) and read only the summary; open the details only if something fails. If a test fails, run it again: if it passes the second time, mark it as flaky, and a single later failure of it is not enough to undo a block. Then look at `git status --porcelain`: if the checks themselves modified files (snapshots, generated files, a formatter run by the tests), note which, because after every block those same files have to be restored by name.

Before running end-to-end tests, ask whether a development server is open. Many test runners reuse a server already listening on their port (Playwright's `reuseExistingServer`) and would test that instead of the branch.

## 3. Analyse the scope and plan blocks

Sort every finding into a level. Use the project's own linter and formatter where it has them, and only on the files in scope.

**Level 1, mechanical:**
- imports, variables and parameters the branch added and nothing uses;
- a key repeated inside an object or dictionary literal in code (in JSON or YAML it depends on the program that reads it, so that is level 2);
- debugging output the branch added (`console.log`, `print`); output the program means to produce (a command-line tool's messages, a server's log) is not debugging, so when in doubt it is level 2;
- commented-out code the branch added, unless a comment beside it says why it is kept (then it is level 2);
- orphan definitions proved to have no references left. An orphaned comment is rewritten, not removed, so it is level 2.

Logs and commented-out code are level 1 here and level 2 in `code-cleanup`: in a branch's own diff they were added moments ago and the user knows why, while in a whole project old ones may be there on purpose.

Two exceptions move to level 2: imports that run something just by loading, and variables whose value comes from a call whose effect would go with them.

Before calling an import, a variable or an orphan unused, rule out the references frameworks add, which no search for the name finds as a call:
- **names the framework injects:** pytest fixtures used as argument names, imports used only by decorators or dependency injection, `import React` in JSX under the classic runtime, imports used only in a Vue or Svelte template;
- **names written as strings in configuration:** Django settings, entry points in `package.json` (`main`, `bin`, `exports`) or `pyproject.toml`, test and build configuration;
- **files reached by URL:** the `public/` folder of Vite and similar tools, a service worker registered with a string, icons in a web app manifest, assets named in HTML.

The reverse trap: a re-export in an `index` file or an `__init__.py` is not a use. Count only the files that import the name, or a barrel nobody imports keeps everything it re-exports looking alive.

**Level 2, needs judgement:**
- repetition inside the diff: the same selector list, condition or helper written twice, which can be merged (`:is()`, one function, one shared test helper);
- names that break the project's own conventions, documented or followed consistently by the surrounding code; your own taste is not a convention, and where the project has none this item does not apply;
- convoluted conditionals the branch added;
- comments the branch added that say what instead of why, or that no longer match the code as it ended up;
- stale comments right beside changed code;
- styles the branch added that end up never applying, because a later rule overrides them or a selector whose names do exist matches no element. Whether they apply depends on the page, not on a search, so removing them needs the visual check in step 4.

**Level 3, summary only, never applied:**
- behaviour changes and bugs, each with file and line, a failure scenario (trigger, path the code takes, wrong result; without one it is only a possible issue, and says why), how it was checked (`traced` end to end, `read` without following the trigger, or `would need running`), and a severity on the same three levels as `branch-review` and `code-cleanup`: **critical** (a person loses data or the app stops working in a normal path), **important** (a wrong result or dead end a person can see, or a crash with specific but plausible data), **minor** (an edge case, or an inconsistency that will become a bug);
- anything touching stored data, authentication or payments;
- a block moved here because it could not be checked (step 4). It has no defect behind it, so it needs no scenario: it is **minor**, with the reason it could not be checked.

What is outside the scope is not level 3: it goes in its own list, "Seen outside the scope", one line each, with no severity.

Group the findings into **blocks**: one topic each, small enough to review in a couple of minutes, ordered from lowest to highest risk. A branch usually yields two to six. More than about eight means the branch is too large for one pass: propose splitting it by file or across sessions. Show the user the plan: each block in one line, then the level 3 list, then "Seen outside the scope". Wait for a go-ahead before step 4, unless the user has already approved every level the plan applies (level 3 is never applied, so it needs no approval): then say you are starting and go on, so they can still stop you.

**Tools, sized to the diff.** A small diff is cheaper and just as well served by reading it yourself; a tool that fans out into several reviewers is worth its cost only when there is more code than one careful read covers.

- **Up to about 150 changed lines** (insertions plus deletions in the `--stat` total from step 1): read the hunks yourself and find the level 2 changes without `/simplify`.
- **Above that**, use `/simplify` to suggest level 2 changes. It applies its fixes to every uncommitted change in the tree, so run it only right after a commit, when the tree holds nothing but its own proposals, and undo anything it does outside the scope or outside the block's topic.
- **At any size**, use `/code-review` for level 2 blocks that change logic (merged functions, rewritten conditionals), never for blocks that only remove, rename or regroup.

Check a tool appears in the session's skill list before relying on it, and invoke it for real rather than imitating it. The names in this file (`/simplify`, `/code-review`, `systematic-debugging`, `branch-review`) are examples: a session may list one under a plugin prefix (`superpowers:systematic-debugging`), under another name, or not at all. Match by what the skill's description covers; when a candidate has no description, its name is the only evidence, so say so; when two candidates cover the same thing, pick one and say which.

## 4. Apply block by block

For each block, in order:

1. **Explain** what changes and why it is better, with the files and a short before-and-after.
2. **Ask**: apply, skip, or see the full change first. If the user has approved every block of a level, do not ask again for those.
3. **Apply** it, keeping to the block's topic and inside the scope.
4. **Check:**
   - Re-run the fast checks. Run the slow ones too if the block changes anything visible. Then restore by name (`git restore -- <file>`) any file the checks modified that the block does not touch, the ones noted in step 2; never with `.` or `:/`, which would undo the block too.
   - If the block touches styles or anything shown on screen, the tests are not enough: they rarely check how things look. Compare before and after, with the computed styles of the affected elements or with screenshots, using the browser if the session has one. If it cannot be checked, do not apply the block: move it to level 3. The one exception is a definition used only by name, proved to have no references left: keyframes no `animation` names, a custom property no `var()` reads, a class whose name appears nowhere, not even built from text. Removing it cannot change what is shown, so the search from step 1 is its check.
   - On a new failure, undo the block by naming its files: `git restore --staged --worktree -- <file> <file>…`. Delete by name any file the block created. Never undo with `.` or `:/`, and never `git clean`. If the block touched dependencies (`package.json`, `requirements.txt`...), restoring those files does not put `node_modules` or the virtual environment back as they were: they need a reinstall with the project's package manager (`npm ci`, `pip install -r requirements.txt`...). A reinstall downloads packages and runs their install scripts, so name the command and wait for a yes; until it runs, the checks would test the wrong dependencies, so run none. Say what happened in one sentence and note it. If investigating is worth it, use `systematic-debugging` rather than improvising.
5. **Commit** the block alone, with `git add` of its files and a message in the project's commit style (`git log --oneline -10` shows it), for example `refactor(theme): merge the dark and light hover selectors`.
   - If a hook rejects the commit and the block caused it, undo the block as above.
   - If the failure was already there, stop and ask: drop that file from the block, skip the block, or let the user decide about the hook.

Between blocks, one line per finished block is enough.

## 5. Wrap up

1. Run all the checks, fast and slow, on the branch as it now stands.
2. Compare `git diff --shortstat <merge-base>...HEAD` with the figure from step 1: the lines the branch adds, before and after the cleanup.
3. Write a short section for the pull request description, in the language the project uses for pull requests (recent PRs or `CLAUDE.md` show it; if neither does, the user's):

   ```markdown
   ## Cleanup
   - Applied: <block in one line> (<short sha>)
   - Skipped: <block> — <why>
   - Left for later (not applied): <finding>, <file:line>, <severity>
   - Possible issues: <finding>, <file:line> — <why it could not be confirmed>
   - Seen outside the scope: <one line each, if any>
   ```

4. Tell the user what is left to them: reviewing the commits (`git log <start>..HEAD`), opening the pull request, merging. Do none of it yourself.

## If the user leaves halfway

The commits already made keep the progress. On return, check the branch (`git branch --show-current`) and that the tree is clean, rebuild the scope from the same base as in step 1, and list the blocks done with `git log <start>..HEAD`. Before the next block, run the fast checks once: dependencies, tools or the machine may have changed in between, and a failure that appeared while nobody was working must not be blamed on the next block. If they fail, say so and ask before going on. If the starting point was lost, the cleanup commits are the ones whose topic is cleanup after the branch's last feature commit; confirm with the user before carrying on.
