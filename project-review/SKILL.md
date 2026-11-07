---
name: project-review
description: Read-only bug hunt across a whole project or one folder, not just one branch. Maps the code, ranks its areas by risk (stored data and migrations first, then error paths at the edges, then the code that changes or breaks most) and reviews them one area per pass through two lenses, silent failures and type design. Every finding has a file, a line, a concrete failure scenario and a severity; the report says which areas were reviewed, at which commit, and which were not, and groups the findings into fix branches in order. It edits no code and makes no commit; it writes only its own report, kept out of git, after asking. Use it whenever the user wants an existing project or folder checked for bugs — "review the whole project", "find what is broken in this codebase", "audit this folder for bugs", and in Spanish "revisa todo el proyecto", "busca fallos en el proyecto", "¿qué falla en este código?". For one branch or pull request, branch-review; to tidy rather than hunt, code-cleanup.
allowed-tools: Read, Grep, Glob, Bash(git rev-parse:*), Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git ls-files:*), Bash(git grep:*), Bash(git diff:*), Bash(git show:*), Bash(git remote:*), Bash(rg:*), Bash(wc:*)
---

# Project review

The goal is to find what **this project gets wrong**: the places where an error disappears without a trace, where the screen keeps looking alive after something died, where two parts of the code disagree about a rule, where a type lets in a state the code cannot handle. Nothing is fixed here. The output is a list of defects a person can act on, each with the exact place and the exact way it fails, and an honest account of where nobody has looked yet.

The difference from a branch review is scale. A diff can be read whole; a project cannot. So this skill decides where to look first, says so, and never lets an area nobody reviewed pass for a clean one.

Whoever uses this skill may not be a seasoned programmer: they can follow a finding to its line but not always tell a real bug from a reviewer's taste. So every finding earns its place with a scenario they could reproduce, and everything that is only an opinion stays out. Speak the user's language.

## Rules that do not bend

- **Read only, except the report.** Never edit, create or delete a project file, never commit, stash, check out or switch branches, and never run the project's tests, build or app: a review that changes the tree is no longer a review of it, and running the app can write data. The only writes are this skill's own report and the line that keeps it out of git (step 1.8), and only after the user says yes. That is why `allowed-tools` leaves out Write and Edit: those two writes always ask for permission.
- **Coverage is stated, never implied.** Every area is listed as reviewed (at which commit), skipped (why) or not reached. A short list of findings over three areas of twelve is a report on three areas.
- **No finding without a failure scenario.** A finding names the input or state that triggers it, the path the code takes, and the wrong result. If that sentence cannot be written, it is not a finding.
- **Conventions come from the project, not from you.** Its `CLAUDE.md` and its code say how it logs, names things and handles errors. A pattern you have seen elsewhere is not a finding here unless the project asks for it. A comment or a spec that promises a behaviour counts as the project asking.
- **Secrets:** never read out or copy keys, tokens or passwords. Flag each one as critical, saying where it is (file, or commit and path) and never the value.
- **No AI signatures** in the report or anywhere else.
- Where a step says to ask something the user has already answered in the conversation (the folder, the go-ahead, the report file), use that answer.

## 1. Scope and map

1. **The folder.** The project root (`git rev-parse --show-toplevel`) or the folder the user names. Without git the review still works, but there is no history to rank by and no commit to pin each area to: say so.
2. **The starting point.** `git rev-parse --short HEAD` and `git status --porcelain`. Every area is recorded with the commit it was reviewed at. Uncommitted changes are reviewed as they stand on disk; say so in one line, and mark those areas as reviewed on a dirty tree.
3. **Out of the analysis:** everything `.gitignore` covers in the tree (the history is step 5's), generated code (`dist/`, `build/`, `out/`, `coverage/`), vendored third-party code, minified files and lock files. If unsure whether something is generated, ask. Out of the analysis means no findings there: reading a dependency to follow a scenario through it is still part of tracing.
4. **What the project already knows.** Read `CLAUDE.md` and what it points at, any decisions or history file, a TODO list, the "Pending" of a `code-cleanup` report (`.cleanup/report.md`) and an earlier report of this skill (`.review/report.md`). A defect already recorded there is not a finding: it is one line under "Already known", with where it is recorded ("this conversation" when the user only said it). Read the CI configuration too (`.github/workflows/*.yml` and the like): what it runs is what the project actually relies on, and it tells which areas no check ever exercises.
5. **Secrets in the history.** `git log --all --diff-filter=A --name-only --format=%h -- '*.env' '*.env.*' '*.pem' '*.key' '*.p12' 'id_rsa*'` lists every such file ever added and its commit, without opening any. Leave out templates (`.env.example`, `.env.sample`, `.env.template`). A file listed there and gone from the tree is still in the history: flag it as critical, by commit and path, as a finding of no area. If `git remote -v` shows a remote, say the file is there too. The fix is rotating the key where it was issued, outside the repository; rewriting history is the user's decision, never this skill's. Never open the file to check what it holds. Secrets written inside source files turn up in the area passes, under the same rule.
6. **The map.** List the files (`git ls-files`, sizes with `wc -l`) and group them into **areas** by role, following the folders where they already mean something: entry points, the data layer (stores, schemas, migrations), the boundaries (network, files, other processes, permissions, imported data), authentication and payments, the user-facing flows, shared utilities. An area is what one careful pass covers: as a rule of thumb, up to about 1,500 lines of source. Split larger ones. Stylesheets count as source but get no line-by-line pass: read them for what the code repeats or relies on (a width the code also computes, a `white-space` the data model depends on). Keep the split by role even in a small project, a few lines per area if need be: the report then says what each finding and each "found sound" covers. Tests, configuration and CI are not areas; they are read with the areas they check.
7. **The ranking**, highest risk first:
   1. **Stored data**: migrations, schema changes, save and load paths. A mistake there costs a person their data, and it runs once on data nobody can recreate.
   2. **Boundaries and error paths**: where outside input comes in or an operation can fail for reasons the code does not control.
   3. **Hotspots**: the files that change most and the ones fixes keep landing on. `git log --since="6 months ago" --format= --name-only` gives the changes per file; `git log --grep="^fix" --format= --name-only` gives the files fixes have landed on. Count them yourself from the output, source files only: documentation, plans and tests that change often say nothing about the code's risk. A history of a handful of commits says nothing here: say so and rank without it. Hotspots decide where to start, not where the findings will be: a file fixed many times may be one already well combed.
   4. **Thin checks**: an area whose files no test imports or names, that no CI job exercises, or whose failure paths no test pins (storage full, a refused read, a missing record) moves up one row. End-to-end flows that walk the whole app rarely take its error paths, so they do not count for the last one.
   5. Everything else.
8. **Show the map and ask.** Each area in rank order in one line: name, size, why it ranks there; then any secret found in the history. Then how many areas fit in this session (two to four is typical) and what each costs, in lines to read: the files of the area plus what they call, read once in this session. A new session has seen nothing, so it rereads whatever it needs from earlier areas: count that too. Ask two things, unless already answered: the go-ahead for the planned areas in that order, and whether to keep the report in `.review/report.md`, excluded from git by adding `.review/` to `.git/info/exclude` (never to `.gitignore`, which is a project file). Without the file the report lives only in the chat and the next session starts the map again; say so. With it, write the map now, following `references/report-template.md`.

## 2. Review one area

Read in this order and stop when the question is answered:

1. **The area's entry points and the data that flows through them.** In a long file, find the symbols with the Grep tool, `rg` or `git grep` and read a line range around them, not the whole file.
2. **Every exported symbol, followed to its callers**, inside the area and outside it. This is where most real findings live: the caller that assumes a value is never null, the screen that reads a flag the service stopped setting, the second copy of a rule. Follow **values** as well as symbols: a shape of data one layer produces (a line break inside a text, an empty string, an id format) can travel through the store and the view to code that calls nothing in the producing area. Ask what shapes of data reach each piece of code, and who produces them.
3. **The tests that mention those symbols**, to know what is already pinned and what is not, and with which inputs: a suite that never feeds a shape another area produces leaves that shape unpinned, however large it is.
4. **The stack reference**, if it applies. When the project uses React, TypeScript, ProseMirror, Dexie, Vitest or Playwright (look at `package.json`), read `references/web-stack.md` before the lenses.

### Lens one: silent failures

The question for every error path: **who finds out, and how?**

- **Swallowed errors:** a catch that returns a default, an empty list or null and moves on; a promise or future with no failure handler; a result checked for success but not for failure. It matters when the default looks like a legitimate result.
- **Fallbacks that lie:** code that retries, substitutes or degrades without saying so, when the user would have chosen differently had they known.
- **Screens that look alive but are dead:** a button wired to something that no longer works, a state never updated after a failure, a loading indicator the failure path never clears.
- **State that dies with its view:** when an error, a warning or unsaved work lives in a component, list every way that component goes away (switching tab, navigating home, closing a panel, a route change) and check that each one keeps it or reports it.
- **Work that never completes:** a callback set on the success path and forgotten on the failure path; a background scope where one failure stops everything after it.
- **Cancellation mistaken for failure**, and the reverse.
- **Errors at the edges:** storage full or corrupt, a permission revoked, a file moved, a provider returning nothing, a second window holding a lock.
- **Logic a test would have caught:** wrong results that raise nothing. `part10` sorting before `part2`, an off-by-one at the end of a list, progress saved under the wrong key. Trace a concrete input and write down where the value goes wrong.

### Lens two: type design

The question: **what does this type promise, and what makes the promise true?**

- **Identity that can collide or drift:** an id built from a hash, a lowercased name or a truncation; a key that includes something the user can change without noticing, when stored data depends on it.
- **One value, two meanings:** zero for both "not started" and "finished", null for both "loading" and "failed".
- **State in several fields that must agree**, with a combination nothing handles.
- **The same rule written twice**, above all in two areas: validation in the form and in the store with different limits.
- **Trust boundaries without a check:** data from a file, a network or another process taken into a type that assumes it was validated.
- **Invariants stated but not enforced**, only when the code already relies on them.

**Contracts between areas** are where a project-wide review finds what a branch review cannot: one area produces a value, another consumes it, and they disagree (the store returns `undefined` for a missing record, the screen expects it to throw). When the other side is in an area not yet reviewed, note the contract in the report so that area's pass checks it.

## 3. Verify before reporting

About a third of what a reviewer first writes down tends to be noise: hypothetical exceptions, preferences dressed as bugs, inflated severities. After this step the rate can fall to none; that is what it is for. Every candidate goes through this:

1. **Write the scenario:** trigger, path (file and lines), result. No scenario, no finding: it goes to "Possible" with the reason, or it is dropped. Take line numbers from reading that one file or from `grep -n`, never from a listing that numbers several files in one run.
2. **Look for the guard** upstream and downstream: a caller that checks, a test that pins the case, a platform that cannot produce that input. If the guard exists, drop the finding; if it is fragile, say so instead of presenting the bug as live. A guard that is only timing (a second click slower than a read) makes a finding when the gap grows with the data or the result cannot be undone, and a "Possible" otherwise. The same check applies to what goes under "Possible".
3. **Say how it was checked:** `traced` (followed end to end), `read` (the pattern is there, the trigger not followed to a concrete input) or `would need running` (only the app can tell). For `would need running`, say what would settle it and where: a test the project can run, or a device or account only the user has. A fix nobody can check is worth knowing before its branch starts.
4. **One finding per root cause.** Five symptoms of one missing handler are one finding with five effects.
5. **Drop what is not a defect:** missing tests, style, naming, dead code (that is `code-cleanup`'s), a type that could be richer without letting any wrong state through, and anything already known.

**Severity**, on the same three levels as its siblings:

- **Critical:** a person loses data or the app stops working in a path a person reaches normally. A secret in the code or the history is always critical.
- **Important:** a wrong result or a dead end a person can see, or a crash with specific but plausible data.
- **Minor:** wrong only in an edge case, or an inconsistency that will become a bug as the code grows.

More than two critical findings in one area means the area is in real trouble or the bar has slipped: say which in one sentence.

## 4. Record and move on

After each area, update the report: the area's status and commit, its findings, its possible issues, the contracts it leaves for other areas, and two or three lines on what was checked and held up. In the chat, one line per finished area is enough.

Stop when the areas planned for this session are done. Every message resends the whole conversation, so several short sessions cost much less than one long one: propose closing this one and carrying on in a new session from the report, and offer the brief for it: the report's path, the areas left in order, the open contracts and the estimate for the next pass, rereads included. Where the host can start a session, offer to start it with that brief; where it cannot, give the brief as text to paste.

## 5. Close

In the chat, in the user's language, give the findings so far, most severe first, and the coverage line ("reviewed 4 of 11 areas; not reached: …"). Then the **recommended order**: the findings grouped into fix branches, each one root cause or one area, most severe first. For each branch, name the files it touches, so the user can see which branches can run side by side. A secret in the history comes first, as a step outside the repository: rotating the key. Each branch is separate work, and `branch-review` before merging it is the check that fits; once the fixes are in, `code-cleanup` is the sibling for tidying. The names are examples: a session may list them under a plugin prefix or not at all; match by what the skill's description covers.

Close with what is left to the user: reading the findings, deciding which to fix and in what order. Do none of it yourself.

## If the user asks for fixes

Fixing is a separate task with separate risks, which is why this skill does not do it even when asked in the same breath. Say so in one sentence, leave the findings as they are, and point at the recommended order: one fix branch at a time, or a few at once when their files do not overlap, with the project's tests after each and `branch-review` before merging. Say what parallel branches still share (a test server on a fixed port, a shared status file, the user's attention), since that part still goes one at a time. Once the fixes land, the report can record each finding's status and where the review closes, as `references/report-template.md` shows.

## Resuming

Read the report. For each reviewed area, `git diff --stat <its commit> HEAD -- <its paths>`: an area changed since its pass is **stale**, and goes back into the ranking. If HEAD has moved, check that the findings of the areas you rely on still stand at their lines before repeating them; if it has not, nothing is stale and they need no rereading. Before reading anything new, give the plan and its cost again as in step 1.8, counting what this session must reread from earlier areas, and wait for the go-ahead. Then carry on from the first area not reached, and say in one line what changed since the last session.

## Cost

One reader, no fan-out: the area's files, what they call and the tests around them, read once per session. Splitting areas across parallel subagents finds no more and costs several times as much; do it only if the user asks for it, and say the price first. Before the first pass, state the estimate from the map (lines in the planned areas); after it, say what the pass actually cost, so the next estimate is real.
