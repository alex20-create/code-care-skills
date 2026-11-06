---
name: branch-review
description: Read-only review of only what one branch adds — a feature, a delivery, a PR in the making — before it is merged, hunting real defects through two lenses, silent failures (errors swallowed or never shown, dead screens, logic a test would catch) and type design (colliding ids, one value with two meanings, invariants nothing enforces, one rule written twice). Scope is the branch's diff from the merge base and nothing else. It edits no file and makes no commit; every finding has a file, a line and a concrete failure scenario, plus a `## Review` section for the pull request. Use it whenever the user wants the current branch, delivery or pull request checked for bugs before opening or merging it — "review this branch", "check the new code for bugs before the PR", and in Spanish "revisa esta rama", "busca fallos en lo de esta entrega", "¿qué se nos ha escapado antes del PR?". Sibling of branch-cleanup, which tidies without hunting bugs; when both are wanted, review first. A whole project or folder is code-cleanup.
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git merge-base:*), Bash(git branch:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(git show:*)
---

# Branch review

The goal is to find what **this branch gets wrong** before it is merged: the places where an error disappears without a trace, where the screen keeps looking alive after something died, where two pieces of code disagree about a rule, where a type lets in a state the code cannot handle. Nothing is fixed here. The output is a short list of defects a person can act on, each with the exact place and the exact way it fails.

Whoever uses this skill may not be a seasoned programmer: they can follow a finding to its line but not always tell a real bug from a reviewer's taste. So every finding has to earn its place with a scenario they could reproduce, and everything that is only an opinion stays out. Speak the user's language.

## Rules that do not bend

- **Read only.** This skill reads files and runs `git` queries. It never edits, creates or deletes a file, never commits, stashes, checks out or switches branches, and never runs the project's tests or build: a review that changes the tree is no longer a review of the tree. If a fix is wanted, say so at the end and stop (see "If the user asks for fixes").
- **The scope is a fence.** The branch's own diff, measured from the merge base. A defect in older code that the branch did not touch is one line under "Seen outside the scope", or nothing. Reporting it as a finding would pull the pull request away from what it is about.
- **No finding without a failure scenario.** A finding names the input or state that triggers it, the path the code takes, and the wrong result. If that sentence cannot be written, it is not a finding.
- **Conventions come from the project, not from you.** The project's `CLAUDE.md` says how it logs, how it names things, which tests it runs. A logger, an error registry or a style you have seen elsewhere is not a finding here unless the project asks for it.
- **Secrets:** do not read out or copy keys, tokens or passwords. If the diff adds one, flag it as critical without the value.
- **No AI signatures** in the `## Review` section or anywhere else: no "Generated with", no model names.

## 1. Fix the scope

1. `git branch --show-current`. If it is the default branch, or empty (detached HEAD), stop and explain that there is no branch to review, and ask which one they mean.
2. Find the base, the branch this one will merge into: the one the user or the skill that invoked this one names, else what `CLAUDE.md` says, else `git symbolic-ref --short refs/remotes/origin/HEAD`, else `main` or `master`, whichever exists. Then `git merge-base <base> HEAD`. Everything is measured from that commit, so commits that landed on the base afterwards do not leak into the review.
3. `git status --porcelain`. Uncommitted changes do not stop the review, since nothing here touches them, but they are not in it either: the review covers `<merge-base>...HEAD`. Tell the user in one line that the pending changes are left out, so they do not take a clean report as covering work that was never looked at.
4. `git diff --stat <merge-base>...HEAD`, then the hunks: `git diff <merge-base>...HEAD`. Note the total of changed lines. Up to a few hundred, read every hunk. In the thousands, propose going file by file, across sessions if needed, rather than skimming.
5. Tell the user in two or three sentences: the branch, the base, how many files and lines are in scope, and that the result will be a list of findings and nothing will be changed.

## 2. Read enough to judge

A hunk alone cannot tell you whether an error is handled upstream or a value is checked by its caller. Reading whole files, on the other hand, costs a lot and adds little. Read in this order and stop when the question is answered:

1. **The project's rules:** `CLAUDE.md` and anything it points at, and any record of known issues (a history or decisions file, open items in the pull request description). A defect the project already lists is not a finding; it is a one-liner under "Already known".
2. **The hunks**, all of them.
3. **Every symbol the diff adds or changes, followed to where it is used and to what it calls**: `rg`, `git grep`, or Read with a line range around the match. This is where most real findings live: the caller that assumes a value is never null, the UI that reads a flag the service stopped setting, the second copy of a rule.
4. **The tests that mention those symbols**, to know what is already pinned and what is not.
5. **The stack reference**, if it applies. When the project uses React, TypeScript, ProseMirror, Dexie, Vitest or Playwright (look at `package.json`), read `references/web-stack.md` before the lenses: it lists the failures those pieces have produced before and the checks that catch them.

## 3. Lens one: silent failures

Look for places where something goes wrong and nobody, neither the user nor the developer, gets to know. The question for every error path is: **who finds out, and how?**

- **Swallowed errors:** a catch that returns a default, an empty list or null and moves on; a promise or future whose failure has no handler; a result that is checked for success but not for failure. The failure matters when the default is indistinguishable from a legitimate result: an empty library that means "nothing there" and also means "could not read the folder".
- **Fallbacks that lie:** code that retries, substitutes or degrades without saying so, when the user would have chosen differently had they known.
- **Screens that look alive but are dead:** a button that calls a method on an object that no longer works, a state that is never updated after a failure, a loading indicator that never ends because the failure path skips the line that clears it, a connection that failed once and is never retried while the screen stays open.
- **Work that never completes:** a future, promise or callback that is set on the success path and forgotten on the failure path; a coroutine scope with no exception handler, where one failed write stops everything after it.
- **Cancellation mistaken for failure:** cleanup or a user action that interrupts work and is then logged, reported or retried as if something had broken.
- **Errors at the edges:** storage full or corrupt, a permission revoked, a file moved, a provider returning nothing, a second window holding a lock. Check what the code does on each, and whether a person could tell that path from the normal one.
- **Logic a test would have caught:** this lens is also for wrong results that raise no exception at all. Progress saved under the wrong key because the current item changed before the save ran; `part10` sorting before `part2`; a rule computed in two places with two answers; an off-by-one at the end of a list; a transition that resets the wrong record. Trace the path with a concrete input and write down where the value goes wrong.
- **Comments and docs beside the changed code that are no longer true** also belong here, because a wrong comment is where the next person will trust the code and lose an afternoon. Keep it to the diff's own comments and the ones right next to it.

## 4. Lens two: type design

Look for places where a type, a key or a value admits a state the code around it cannot handle. The question is: **what does this type promise, and what makes the promise true?**

- **Identity that can collide:** an id built from a hash, a lowercased name or a truncation, while grouping or lookup uses something else, so two different things end up with one id or one thing with two. Follow it to where the id is used as a key: a map, a list key, a file name, a stored position.
- **Identity that is not stable:** a key that includes something the user can change without noticing (a folder grant, a path, a display name), when stored data depends on it staying the same.
- **One value, two meanings:** zero that means both "not started" and "finished"; an empty string that means both "unknown" and "none"; null that means both "loading" and "failed". Find the code that reads the value and has to guess.
- **State kept in several fields that must agree:** a connecting / connected / failed machine spread over two nullable fields; a flag on the item and the same flag on its owner; a field written on every change and read nowhere. Find the combination nothing handles.
- **The same rule written twice:** the label says which item will resume and the action picks a different one; validation on the client and on the store with different limits. Two copies drift; one copy cannot.
- **Trust boundaries without a check:** data from another process, another app, a file or a network taken as-is into a type that assumes it was validated: an index never compared against the list, a URI played without resolving it, a payload trusted because it arrived on the right channel.
- **Invariants stated but not enforced** only count when the code already relies on them: a doc comment saying "must be non-empty" over a list that one caller builds empty is a finding; a value class that would merely be nicer is not.

## 5. Verify before reporting

The trial that shaped this skill found that about a third of what a reviewer first writes down is noise: hypothetical exceptions, design preferences dressed as bugs, severities inflated to be noticed. Every candidate goes through this before it reaches the report.

1. **Write the scenario** in one or two sentences: the trigger (input or state), the path (file and lines the code takes), the result (what the user or the data ends up with). No scenario, no finding: it goes to "Possible" with the reason it could not be pinned down, or it is dropped.
2. **Look for the guard** upstream and downstream. A caller that checks the value, a test that pins the case, a platform that cannot produce that input. If the guard exists, drop the finding. If it exists but is fragile, say so in the finding instead of pretending the bug is live today.
3. **Say how it was verified:** `traced` when the path was followed by reading the code end to end; `read` when the pattern is there but the trigger was not followed to a concrete input; `would need running` when only the app can tell. The user decides how much weight to give each.
4. **One finding per root cause.** Five symptoms of one missing error handler are one finding with five effects, not five findings.
5. **Drop what is not a defect:** missing tests (that is a different task), style, naming, a type that could be richer without any state it currently lets through, an exception a platform declares but does not produce in practice unless the handling path would lose data, and anything the project already records as known.

### Severity

Three levels, with the test for each:

- **Critical:** a person loses data or the app stops working in a path a person reaches normally.
- **Important:** a wrong result or a dead end a person can see, or a crash in a path that needs specific but plausible data.
- **Minor:** wrong only in an edge case, or an inconsistency that will become a bug when the code grows.

More than two critical findings on one branch means either the branch is in trouble or the bar has slipped; say which in one sentence under the list.

## 6. Report

In the chat, in the user's language:

```markdown
# Branch review: <branch> against <base>

<files> files, <lines> changed lines, from <merge-base short sha> to <HEAD short sha>.
Uncommitted changes present and not reviewed. (only if there are any)

## Findings
1. **<Critical | Important | Minor>** · `<file>:<line>` · <one-line title>
   Scenario: <trigger → path → result>
   Verified: traced | read | would need running
   Fix (not applied): <one line, or "none obvious">

## Possible
- `<file>:<line>` · <what looks wrong and why it could not be pinned down>

## Already known
- <one line each, with where the project records it>

## Seen outside the scope
- <one line each; nothing if there is nothing worth a line>

## Looked at and found sound
- <two or three lines on what was checked and held up, so a short list is not mistaken for a shallow one>
```

Then a section to paste into the pull request description, in the language the project uses for pull requests (recent pull requests or `CLAUDE.md` show it), with the same findings in one line each:

```markdown
## Review
- Critical: <finding> (`file:line`)
- Important: <finding> (`file:line`)
- Minor: <finding> (`file:line`)
- Possible: <item>
- Seen outside the scope: <item>
```

Close with what is left to the user: reading the findings, deciding which to fix, and how (a fix commit on this branch, a follow-up, or nothing). Do none of it yourself.

## If the user asks for fixes

Fixing is a separate task with separate risks, which is why this skill does not do it even when asked in the same breath. Say so in one sentence, leave the report as it is, and offer the way forward: the user applies the fixes themselves or asks for them as a normal task, one finding at a time, with the tests run after each; `branch-cleanup` is the sibling for tidying the same scope, not for fixing logic.

## Cost

One pass, no subagents, no fan-out: the hunks, the symbols they touch and the tests around them. Reading beyond that is what makes a review expensive, and the trial behind this skill showed that a single careful reader with the two lenses above finds the same defects as a parallel fan-out of specialised reviewers at a fraction of the cost. If the diff is too big for one careful pass, say so and split it rather than skim it.
