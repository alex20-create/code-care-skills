---
name: code-cleanup
description: Guided, safe code cleanup of a whole project or one folder (JavaScript, TypeScript, Python or other). Works on a new branch, uses the skills, plugins and subagents already installed, can search for new skills if the user wants and asks before installing any, and applies changes in blocks the user approves one at a time, checking that everything still works after each block. Use it when the user asks to clean up, tidy, sanitise or simplify the code of a project or folder, remove dead code, unused imports, debug logs or duplicates, or get a repo ready before launching or showing it, even if they never say "cleanup". For only what one branch adds use branch-cleanup; to hunt bugs in a branch, branch-review; for one function or file, just edit it. Also use for "clean up this codebase", "tidy the repo", "remove dead code", "cleanup pass", and in Spanish for "limpia el código", "ordena el repo", "quita código muerto".
---

# Guided code cleanup

The goal is to leave the project cleaner **without changing what it does** and without the user losing anything. Whoever uses this skill may not be a seasoned programmer: they can follow commands but not diagnose a failure. That is why safety (a separate branch, one commit per block, checking after every change) matters more than speed, and every step is explained in plain language: what is about to happen, why, and how to undo it.

Speak the user's language, and write the report and the baseline in it too. If it is Spanish, use European Spanish. Both files are local working notes excluded from git, so a rule that what goes into a repository is written in English does not cover them, unless a `CLAUDE.md` names them.

If the user only wants what one branch adds tidied, before its pull request, that is `branch-cleanup`; if they want a branch checked for bugs, that is `branch-review`. Say so in one line and let them choose before Phase 0.

## Non-negotiable rules

These rules exist because a mistake here can cost the user real work:

- **The project's and the user's `CLAUDE.md` govern conventions**: branch names, commit style, language, how to run the tests, asking before writing. Follow them even where this skill says otherwise. What they never do is lower the safety rules in this list (a separate branch, no `merge`, `push` or `stash`, no behaviour change, no skipping hooks). If a `CLAUDE.md` clashes with one of them (for example, "work directly on main"), stop and ask the user before going on.
- **Do not touch the starting branch.** Everything happens on a new branch. Never `merge`, `push`, `rebase`, `reset --hard`, `push --force`, `stash` or delete branches. That is the user's call at the end. The only exceptions are the initial commit of a brand-new repository (Phase 0, step 1) and the commit of their pending work (Phase 0, step 3): both only with their explicit approval and before the cleanup branch is created.
- **Do not change behaviour.** Cleaning is not adding features or "fixing" logic. If you see a bug, note it in the report; do not fix it inside the cleanup.
- **Never skip hooks.** If a pre-commit hook fails, do not use `--no-verify`: treat it as a failure of the block (Phase 5, step 5).
- **No AI signatures.** In commits, comments, READMEs or descriptions, add no `Co-Authored-By`, "Generated with..." or anything that mentions AI. Plain, descriptive commit messages.
- **Secrets:** do not read out or copy keys, tokens or passwords you come across. If one appears in the code, flag it as critical in the report (without showing the value) and do not move it yourself. The same goes for a `.env` or credentials file that is stored in git (`git ls-files` lists it) or ever was (`git log --all --oneline -- ":(glob)**/.env*"` also finds those deleted later, in any folder): even if it is gone now, it is still in the history, so the key has to be rotated. Explain this to the user and leave it alone. To see what such a file held without reading the values, list only the names: `git show <commit>:<path> | sed 's/=.*/=<redacted>/'`. That search also lists templates meant to be committed (`.env.example`, `.env.sample`, `.env.template`): flag one only if it holds what looks like a real value rather than a placeholder, and say which without showing it.
- **Do not hand-edit** `.env*`, credentials, data migrations or lock files (`package-lock.json`, `poetry.lock`...). Migrations are not always loose files in a `migrations/` folder: often they are code inside another file, such as Dexie versions with `db.version(2).upgrade(...)` or a list of steps that run when stored data is loaded. They look like ordinary code, but changing them changes what happens to the data the user already has: they are level 3 even if a simplifier sees something to improve. If dependencies have to change, do it with the package manager and in a block of its own.
- **Nothing that downloads and runs code without permission.** That includes `npx`, `pipx`, `uvx` and the like, even just to search: say which package gets downloaded and wait for a yes.

## Phase 0: Safety net

1. Check that the project is a git repository (`git rev-parse --is-inside-work-tree`).
   - If it is not, **stop**. Explain that without git there is no easy way to undo changes and offer to create one. Go on only if the user agrees, and in this order:
     1. `git init`.
     2. If there is no `.gitignore`, propose a minimal one for the stack (at least `.env*`, dependencies such as `node_modules/` or `.venv/`, and build output such as `dist/`). Without it, the first commit would take secrets and thousands of dependency files with it.
     3. `git add -A` and show the list of what is going in (`git status --short`). If anything looks like a secret or a huge folder, stop and ask.
     4. `git commit -m "Initial state before cleanup"`.
2. Check whether the session already runs in a worktree: if the two paths from `git rev-parse --path-format=absolute --git-dir --git-common-dir` differ, it does. In that case read `references/worktree.md` ("If the session is already in a worktree") and do not offer another worktree in step 4.
3. Check for uncommitted changes (`git status --porcelain`).
   - If there are any, **stop and ask**: commit them on their current branch (one of the only two times the starting branch is touched, and only if they approve), work in a worktree (step 4) so they stay where they are (not if the session is already in one, step 2), or cancel so they sort them out themselves. Do not use `git stash`: it is easy to forget what was put aside. Do not mix their pending work with the cleanup.
4. Decide where the work happens. By default, in the same folder on a new branch. Offer a **worktree** (a second folder of the same repository with the cleanup branch checked out) only if there are uncommitted changes the user does not want to commit, or if they want to keep working in their folder while the cleanup runs. If they consider it, read `references/worktree.md` and explain what it costs before they choose.
5. Note the starting branch and commit (`git branch --show-current`, `git rev-parse --short HEAD`).
   - If `git rev-parse HEAD` fails, the repository has no commits: offer the initial commit from step 1 before going on.
   - If `git branch --show-current` returns nothing, the user is not on any branch (detached HEAD: they have a loose commit checked out, not a branch). Explain this and ask which branch they want to start from. Without a starting branch, the closing instructions of Phase 6 do not work.
6. Choose the branch name:
   - If the project documents a convention (in `CLAUDE.md`, `CONTRIBUTING`, or what `git branch -a` shows), follow it; for example `chore/cleanup-YYYY-MM-DD`.
   - If there is none, use `cleanup/YYYY-MM-DD`.
   - With today's date; if it already exists, add `-2`, `-3`...
7. For the report, propose creating a `.cleanup/` folder at the root of wherever the work happens and adding it to `.git/info/exclude` (not to `.gitignore`). That way the report stays on the user's machine but never enters a commit or clutters the repo.
8. Before creating anything, say in one sentence what you are about to create (the branch, the worktree if any, the `.cleanup/` folder and the line in `.git/info/exclude`) and, with a worktree, which command will install the dependencies. Wait for the go-ahead. Installing dependencies downloads packages and runs their install scripts, so it falls under the rule of not running code without permission. Then:
   1. Same folder: `git switch -c <branch>`. Worktree: the steps under "Creating it" in `references/worktree.md`.
   2. Create the `.cleanup/` folder and add the line `.cleanup/` to `.git/info/exclude` (in a worktree, at the path given in `references/worktree.md`).

Explain to the user in two or three sentences what you have done and how to go back. In the same folder, `git switch <original-branch>` brings back their usual version. With a worktree, their folder never changed: they just do not open the other one.

## Phase 1: Understand the project and measure the starting point

1. Read `CLAUDE.md`, `README` and the configuration files (`package.json`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`, `go.mod`, lint and formatter configuration...). Respect the project's conventions even when they differ from your preferences.
2. Find out which checks exist: tests, lint, type checking, build. Look for the real scripts (for example `scripts` in `package.json`); do not invent them. Also read the CI configuration (`.github/workflows/*.yml`, `.gitlab-ci.yml` and the like): it says which checks the project actually relies on, and sometimes runs one that no script names. If the CI runs on systems or versions this machine does not have (Linux and Windows, several Node or Python versions), note it for "What could not be checked" in the report. Split the checks into two groups and note this in the baseline:
   - **Fast** (seconds): unit tests, lint, types, build. They run on every block.
   - **Slow** (minutes): mostly end-to-end tests, which drive the app the way a person would (Playwright, Cypress). They run for the baseline, on blocks that change something visible, and at the end (Phase 6).
3. **Running servers.** Many end-to-end tests start the app or, if one is already open on their port, connect to it (in Playwright, `reuseExistingServer`). If the user has `npm run dev` or similar open, the tests may end up testing that app instead of the branch's code, and nothing will fail. Before running them, ask whether a development server is open and ask the user to stop it while they run.
4. **Run all those checks, the slow ones included, before touching anything**, and save the result and the exact commands you used in `.cleanup/baseline.md`, so they are repeated the same way on every block and in a new session. If something was already failing, it is on record and will not be mistaken for a failure caused by the cleanup. Also note a few measurements that come free with what you already run: line count of the source files in the scope (excluding tests and generated code), build size, the number of tests as the test runner reports it (or the number of test files when it reports none), and the number of linter warnings. At the end they show what changed.
   - **Save the full output to a file and read only the summary.** Redirect each check to a file in `.cleanup/` (for example `.cleanup/tests.log`) and read only the last lines or the pass/fail count. Open the details only if something fails. The same in Phase 5: test output, repeated on every block, is one of the biggest context costs.
   - If a test fails, run it a second time. If it passes the second time, mark it as **flaky**: a later failure of it is not enough to revert a block.
   - When done, `git status --porcelain` must come out clean (the `.cleanup/` folder does not show because it is excluded). If the checks modified files tracked by git (test snapshots, generated files), tell the user, note it in the baseline and restore them by name (`git restore -- <file> <file>…`) before the first block. Not with `:/` or `.`, which would also undo anything the user changed by hand in the meantime. Otherwise those changes would end up mixed into the cleanup commits. If what shows up is new files the checks created (test reports, for example), note them and add them to no commit. In Phase 5 this is done differently (step 4), because by then there are uncommitted block changes.
5. If the project has no tests and no build, say so plainly: the safety net will be weaker. Propose how to verify by hand (starting the app, the `/verify` skill if the session has it) and adjust Phase 4 to be more conservative.
6. If the project is large (hundreds of files), propose narrowing it down: by folder, or starting with what is used most. A partial cleanup done well is worth more than a complete one done halfway.
7. Decide what stays **out of the analysis**: everything in `.gitignore`, generated code (`dist/`, `build/`, `out/`, `coverage/`), third-party code copied into the repo (`vendor/`, `third_party/`), minified files (`*.min.js`, `*.min.css`) and lock files. If you are unsure whether something is generated, ask.

## Phase 2: Inventory of what is already installed

Before looking for anything new, make use of what the user already has. There are three sources:

1. **This session's skill list.** It is already in your context (available skills and subagent types). It is the main source.
2. **The inventory script**, which also finds what is not loaded, the subagents, and the plugins in marketplaces already added. Use it with a filter so you do not get hundreds of lines:
   ```bash
   node "<path-to-this-skill>/scripts/skill-inventory.mjs" --project "<project root>" --search "simplif,cleanup,clean up,refactor,lint,dead code,review"
   ```
   `<path-to-this-skill>` is the base directory the skill tool reported when this skill loaded; the skill may be installed outside `~/.claude/skills`. If no base directory was reported and the script cannot be found, skip it and use the fallback below.
   The filter matches at the start of a word (`simplif` finds `simplify` and `simplification`), sorts by relevance and shows at most 15 results per section (`--max <n>` to change that). It also marks disabled plugins. In a worktree, see `references/worktree.md` for which folder to pass as `--project`. If `node` is not available, look by hand at `~/.claude/skills/*/SKILL.md`, `.claude/skills/*/SKILL.md`, `~/.claude/agents/*.md` and `~/.claude/plugins/`.
3. **The skills bundled with Claude Code**, such as `/simplify`, `/code-review`, `/verify` or `/debug`, if they appear in the session. Do not assume they exist: check the list.

Pick only the ones that add something to this cleanup. The names below, and every skill this file names elsewhere, are examples, not the names to expect: a session may list one under a plugin prefix (`superpowers:systematic-debugging`, `anthropic-skills:branch-review`), under another name, or not at all. Match by what the skill's description covers, and when two candidates cover the same thing, pick one and say which.

| What for | What to look for |
|---|---|
| Simplify code without changing behaviour | `/simplify`, the `code-simplifier` plugin |
| Review level 2 blocks that touch logic | `/code-review`, `code-reviewer`-type subagents |
| Check that the app still works | `/verify`, `verification-before-completion` |
| If something fails after a block | `systematic-debugging`, `/debug` |
| Check at the end that the branch changed no behaviour | `branch-review` (Phase 6) |
| Stack rules (React, Python...) | best-practice skills for the language or framework |
| Close the branch at the end | `finishing-a-development-branch` |

Show the user a short table: skill, where it comes from, what you will use it for. When you use one, actually invoke it with the skill tool instead of imitating what you think it says. A plugin the script marks as disabled is not available: if it would help, tell the user how to enable it. Write the selection into `.cleanup/report.md`, so a new session uses the same ones without repeating this phase.

## Phase 3: Look for new skills (optional)

Unless the user has already said whether they want it, ask whether they want to look for new skills or would rather work with what they have. Explain that searching takes a few minutes and downloads the search tool from npm.

- If they do not want to, go to Phase 4.
- If they do, read `references/find-skills.md` and follow its steps.

This phase never blocks the cleanup: with no network or nothing approved, carry on with what is installed.

## Phase 4: Analysis and a plan in blocks

Go through the code and sort every finding into one of three levels. Use the project's own tools where they exist (its linter, its formatter). External tools such as `knip`, `depcheck`, `ts-prune`, `ruff` or `vulture` are very good at finding dead code, but they download and run code: mention them in the plan and use them only if the user agrees.

If the project has no linter, propose a one-off pass: install the language's linter (ESLint, `ruff`...) in a temporary folder **outside the repository**, run it once over the code and leave nothing installed or added. It tends to find unused variables, duplicate keys and real bugs in one go. It needs the user's permission, because it downloads code. If it turns out useful, adding the linter to the project goes into the report as a recommendation, to be done later on its own branch, not inside the cleanup.

**Start from what the project already knows.** Read its record of known issues before sorting anything: `CLAUDE.md` and what it points at, a decisions or history file, a TODO list, the "Pending" of an earlier `.cleanup/report.md`. A defect it already records is not a new finding: it goes in one line under "Already known" in the report, with where the project records it, so the user is not told again what they wrote down themselves.

**Do not read whole files to search.** Locate with searches (`rg`, `git grep`), with the linter or with an exploration subagent, and read only the lines around each match. In a file thousands of lines long, reading it whole costs a lot and adds nothing.

**Level 1: safe and mechanical.** Unused imports and variables, with three exceptions that move to level 2:
- Imports that run just by loading, bringing in no name: `import "./styles.css"`, a polyfill, a module that registers something when imported.
- Imports that are really re-exports: in `__init__.py` or an `index.js`/`index.ts`, other files use them through that file.
- Variables whose value comes from a call (`const x = save()`): deleting the variable would also delete the call and what it does.

Also level 1: a key repeated inside the same object or dictionary literal in JavaScript or Python code. Only the last one counts, so removing the earlier ones changes nothing. In JSON or YAML it depends on the program that reads it (some raise an error): that is level 2.

**Level 2: needs judgement.**
- Duplicate functions that can be merged, very long functions, confusing names, convoluted conditionals. Confusing and convoluted by the project's conventions (documented, or followed consistently by the code around them), never by your own taste: where the project has no convention on something, it is not a finding.
- Files that seem unused and dependencies that seem unnecessary.
- Logs (`console.log`, `print`...): some are forgotten debugging, but others are the program's real output (a command-line tool, a server's log). Explain each case.
- Blocks of commented-out code: they may be there on purpose (an alternative, a feature switched off for now).
- Styles (CSS) that apply to no element, because a later rule overrides them or a selector whose names do exist matches nothing. Whether they apply depends on the page, not on a search, so removing them needs the visual check of Phase 5. A definition used only by name is different: keyframes no `animation` names, a custom property no `var()` reads, a class whose name appears nowhere, not even built from text. Proved unreferenced, it is level 1, and the search is its check.
- Translation strings (i18n keys) that no code reads. Also check whether the code builds the key's name from text.
- Outdated comments and documentation: comments that no longer describe the code, or a `README` or `CLAUDE.md` that says something the code no longer does.
- Configuration options that have no effect (from a tool no longer used, or ignored by the installed version).
- Formatting: only with the formatter the project **already has configured**, never a new one. It goes in a block of its own, the last one, because it touches many lines and makes the diff hard to review.

**Level 3: report only, not applied.**
- Architecture changes and any behaviour change.
- Renaming or removing something code outside the repo may use. In a library or published package, an export nobody uses inside the repo may be used by another project.
- Upgrading dependency versions.
- Anything touching authentication, payments or stored data.
- Bugs found and secrets in the code.

Level 3 is not applied, but it has to be usable for fixing things later. Each finding carries:
- **Severity**, on the same three levels `branch-review` and `branch-cleanup` use for defects:
  - **critical:** a person loses data or the app stops working in a path a person reaches normally;
  - **important:** a wrong result or a dead end a person can see, or a crash in a path that needs specific but plausible data;
  - **minor:** wrong only in an edge case, or an inconsistency that will become a bug as the code grows.

  Two kinds of level 3 item fall outside those tests. A secret in the code or in the history is always **critical**. An item with no defect behind it (an architecture change, a dependency upgrade, code health) is **minor**.

  If more than two bugs met in passing come out critical, either the project is in real trouble or the bar has slipped: say which in one sentence under the list.
- **Fix risk:** safe, needs the tests, or needs a manual check in the app. A secret's fix risk is always "manual, outside the repository": the key is rotated where it was issued. Size and how it was checked do not apply to a secret: write "n/a" and say where it was found (file, or commit and path).
- **Size:** XS (under 10 lines), S (10 to 40), M (40 to 150), L (over 150).
- **File and lines, and how it was checked:** `traced` (the path was followed by reading the code end to end), `read` (the pattern is there but the trigger was not followed to a concrete input) or `would need running` (only the app can tell).

A cleanup is not a bug hunt: the bugs here are the ones met on the way. Each still has to earn its place (secrets and items with no defect behind them need none of this):
- **A failure scenario** in one or two sentences: the trigger (input or state), the path the code takes (file and lines), the wrong result. If that sentence cannot be written, it goes under "Uncertain findings" in the report with the reason, not into the level 3 list.
- **A look for the guard** upstream and downstream: a caller that checks the value, a test that pins the case, a platform that cannot produce that input. If there is one, drop the finding; if it is fragile, say so instead of presenting the bug as live.
- **One finding per root cause:** five symptoms of one missing check are one finding with five effects.

If the user wants a real hunt for bugs, that is `branch-review`, run on a branch; mention it in the report rather than turning the cleanup into one.

At the end, propose a **recommended order** in groups, each meant as separate work on its own branch, from most to least severe. In a mature project, level 3 may well be the most valuable part of the whole cleanup.

Before declaring a file, function, CSS class or key "unused", look for indirect references: dynamic imports, paths by file name, configuration, templates, tests, and above all names built from text (`"nav" + id` uses the class `navchallenges` even though that word is written nowhere). If you cannot prove it, move it to level 3. Frameworks add references of their own that no search for the name finds as a call:
- **Names injected by the framework:** pytest fixtures imported into `conftest.py` and used as argument names; imports used only by decorators or dependency injection (NestJS, Angular, `emitDecoratorMetadata`); `import React` in JSX files under the classic runtime; imports used only in the template of a Vue or Svelte component.
- **Names written as strings in configuration:** Django's `INSTALLED_APPS` and URL configuration, entry points in `package.json` (`main`, `bin`, `exports`) or `pyproject.toml` (`[project.scripts]`, plugin entry points), test and build configuration.
- **Files reached by URL, not by import:** the `public/` folder of Vite and similar tools, a service worker registered with `navigator.serviceWorker.register("/sw.js")`, icons and screenshots listed in a web app manifest, assets named in HTML.

Write the plan into `.cleanup/report.md` grouped in **blocks**: each block is a single topic (for example "remove unused imports") and small enough to review in a couple of minutes. Order them from lowest to highest risk, with formatting last. Show the user the plan's summary: number of blocks, what each does in one line, and the level 3 list. Then wait for a go-ahead before Phase 5, unless the user has already approved every level the plan contains: in that case say you are starting and go on, so they can still stop you.

**If the plan has more than about 8 blocks, propose splitting it across several sessions.** Every message resends the whole conversation, so one long session costs far more than several short ones. Propose to the user that they close this session once the plan is written in `.cleanup/report.md`, and apply a few blocks in each new session by reading the report (see "The user leaves halfway" under "If something goes wrong").

## Phase 5: Apply block by block

For each block, in order (when the next block is formatting, first see Phase 6, step 2):

1. **Explain** in plain language what changes and why it improves the project. Show the affected files and a short before-and-after example.
2. **Ask**: apply, skip, or see the full change first. If the user has already said they approve every block of a given level, respect that and do not ask again for those.
3. **Apply** the change yourself, sticking to the block's topic. In level 2 blocks that touch logic you can lean on a selected simplification skill (`/simplify`, `code-simplifier`), but bear in mind that it works on whatever changes exist at that moment and applies fixes on its own: use it after your change, only on the block's files, and undo whatever it does outside the block's topic. Its result goes through the same checks as any other change.
   - If you use the `code-simplifier` subagent: it ships fixed style rules aimed at TypeScript (annotating return types, prop types, preferring `function` over arrow functions) that may not be the project's. Give it the conventions from the project's `CLAUDE.md` in the brief, tell it they override its own and that it must not change behaviour, and undo any change of its that does not follow them.
4. **Check**:
   - Re-run the **fast** checks from Phase 1 and compare them with the baseline. The slow ones only if the block changes something visible (styles, text, interface components); otherwise they wait for Phase 6. A failure of a test marked flaky does not count as a new failure unless it fails twice in a row.
   - Then look at `git status --porcelain`. If the checks modified files the block does not touch again (the same ones as in the baseline), restore them **one by one by name** (`git restore -- <file>`). Never with `:/` or `.` here: the block's change is not committed yet and would be undone too.
   - If the block removes styles (other than the definitions used only by name of Phase 4) or touches anything visible, the tests are not enough: they almost never check how things look. Compare the main screens before and after, with screenshots or with each element's computed styles, using the browser if the session has one. If it cannot be checked, do not apply the block: move it to level 3.
   - Only in level 2 blocks that touch logic (merging duplicates, splitting long functions, simplifying conditionals): if a review skill or subagent was selected (`/code-review`, `code-reviewer`), give it the block's diff. If it finds a behaviour change, drop that part of the block or undo the whole block. For the other blocks (imports, logs, commented-out code, formatting) the checks are enough: a review costs time and tokens and adds nothing.
   - If a new failure appears, undo the block by naming its files: `git restore --staged --worktree -- <file> <file>…`, with the files `git status --porcelain` shows as modified by the block. Never with `.` or `:/`: they undo every change in the folder or the repository, including any the user made by hand while the cleanup ran. Delete by name only the new files that block created (never a blanket `git clean`, which could take the user's things with it). If the block touched dependencies (`package.json`, `requirements.txt`...), restoring those files does not put `node_modules` or the virtual environment back as they were: they need a reinstall with the project's package manager (`npm ci` or `npm install`, `pip install -r requirements.txt`...). A reinstall downloads packages and runs their install scripts, so name the command and wait for a yes, unless the user already approved it for this cleanup; until it runs, the checks would test the wrong dependencies, so run none. Tell the user what happened in one sentence and note it in the report. Do not try to fix it by improvising: if investigating makes sense, use `systematic-debugging`.
   - If everything is the same or better, carry on.
5. **Commit** that block alone: `git add` the files touched and a clear message in the language of the previous commits, which may not be the language of the conversation (check with `git log --oneline -10`), for example `chore: remove unused imports in src/`. One commit per block means any of them can be undone separately with `git revert`.
   - If a pre-commit hook rejects the commit, do not skip it. Read what it says:
     - If the block itself caused the failure, treat it as in step 4 (undo and note it).
     - If the failure already existed (it is in the baseline, for example a lint error in a file the block touched), the commit is blocked through no fault of the cleanup. Stop, explain it to the user and ask: drop that file from the block, skip the block, or let them decide what to do about the hook. Never `--no-verify` on your own.
6. Update `.cleanup/report.md` with the block's status (applied, skipped, reverted).

Between blocks, do not narrate every command. One line per finished block is enough.

## Phase 6: Wrap-up

1. Run **all** the checks, fast and slow, one last time on the complete branch. If a slow check fails here and did not fail in the baseline, the culprit is one of the blocks where it was not run. Since every block has its own commit, it can be found without undoing anything: explain `git bisect` to the user, which tries commits on the branch until it finds the first one that fails, and when done go back to the branch with `git bisect reset`. Do this only with their go-ahead. The guilty block is reverted with `git revert <commit>` and noted in the report.
2. **Offer a read-only review of the cleanup branch**, if `branch-review` appears in the session's skill list. A cleanup branch is exactly the kind of diff that skill was built for: one that should change no behaviour, so any finding is a block that went too far. Explain that it reads every hunk and costs tokens in proportion to the diff, and run it only with a yes:
   - Name the base when you invoke it: the starting branch noted in Phase 0, step 5, not the default branch it would otherwise pick. It always reviews everything from the merge base to `HEAD` and takes no narrower range.
   - That is why, when the plan has a formatting block, the review is offered earlier: when Phase 5 reaches the formatting block, offer it then, before applying the block, so the diff holds no formatter changes (thousands of lines that cannot change behaviour). Apply the formatting block afterwards, and here in Phase 6 only note the outcome.
   - If the diff is still in the thousands of lines, say so and let the user decide whether the review is worth its cost.
   - A finding it confirms means a block changed what the code does: revert that block with `git revert <commit>` (with the user's go-ahead), note it in the report, and re-run the fast checks.
   - Note the outcome for the report: run or declined, the range reviewed, and what it found.
3. Once no block will be reverted any more, take the Phase 1 measurements again for the report's before-and-after table. Taken earlier, a revert in step 1 or 2 would leave them describing code that is no longer there. Then complete `.cleanup/report.md` with the structure in `references/report-template.md`.
4. Explain the user's options step by step, assuming nothing:
   - **Review** all the changes: `git diff <original-branch>...<cleanup-branch>`.
   - **Keep the cleanup**: go back to their branch (`git switch <original-branch>`) and merge it (`git merge <cleanup-branch>`). If they work with GitHub, better to open a pull request from the branch, with the report's "For the pull request" section as its description.
   - **Discard it**: go back to their branch and, if they want, delete the cleanup one (`git branch -D <cleanup-branch>`). Their original code was never touched.
   - **If a worktree was used**: also walk them through the "Wrap-up" section of `references/worktree.md` (merging from their main folder and removing the worktree without losing anything).
   - **Tidy up afterwards**: once they no longer need the report, they can delete the `.cleanup/` folder and remove its line from `.git/info/exclude`.
   Do not carry out any of these options on your own.
5. If `finishing-a-development-branch` is installed, offer it for this step.
6. For the level 3 groups in the recommended order, each of which becomes its own branch: say that `branch-review` before merging each one is the check that fits, since those branches do change behaviour on purpose.

## If something goes wrong

- A baseline check takes a very long time or needs external services (a database, keys): ask before running it and, if it cannot be run, carry on with the ones that work and say so.
- The user leaves halfway: the report and the commits already made keep the progress. On return:
  1. Find where the work was happening. If there is no `.cleanup/` in this folder, look at `git worktree list`: if a worktree was used, the report is in that other folder, and read `references/worktree.md` before going on.
  2. Check that you are on the cleanup branch (`git branch --show-current`) and that there are no stray changes (`git status --porcelain`). If the user switched branches or left changes in the meantime, explain it and ask before going on.
  3. Read `.cleanup/report.md` (the plan, the chosen skills, each block's status) and `.cleanup/baseline.md` (the check commands and their starting results).
  4. Before the next block, run the fast checks once with the baseline's commands. Dependencies, tools or the machine may have changed in between, and a failure that appeared while nobody was working must not be blamed on the next block. If the results differ from the baseline and the last block's notes, say so and ask before going on.
  5. Carry on from the first pending block.
- A commit fails with "Please tell me who you are" or "Author identity unknown": git does not know the user's name or email, which is normal on a machine where it was never set up. Explain this and give them the two commands to run themselves with their own details (`git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"`). Do not make them up or fill them in yourself: they are the user's details and they go into every commit.
- Unsure whether a change is safe: treat it as level 3. Better left in the report than something broken.
- The user asks halfway for a new feature or a fix: do not put it in a cleanup block, however small. Note it in the report and propose doing it later on its own branch. Mixed into the cleanup, it can no longer be reviewed or undone separately.
