---
name: branch-ship
description: Takes one branch from finished code to a pull request ready to push, in a fixed order. It runs branch-review, stops so the user can decide each finding, fixes each chosen finding in its own commit with a test that fails before and passes after, runs branch-cleanup (or skips it for a small fix branch), runs the full suite, and writes a pull request body with Review, Fixes and Cleanup sections. Each step goes into a per-branch record inside .git, so a new session resumes where the last stopped and a push gate can check nothing was skipped. It asks before pushing and never merges. It also builds a fix branch from numbered findings in a project-review report. Claude Code only, since it needs a shell. Use it when a branch should go through review, fixes, cleanup and checks, as in "ship this branch", "take the branch to the PR", "make fix branch 2 from the review report", and in Spanish "lleva la rama hasta el PR", "haz la rama de arreglos 1 del informe". For one of those steps alone, use its sibling skill.
---

# Branch ship

The goal is to take **one branch** from "the code is written" to "the pull request is ready to push", in an order that keeps each step honest. The review runs first, because the fixes are new code that the cleanup should see. The cleanup comes next, and the full suite runs last, on the exact commit that will be pushed. This skill runs the other skills and keeps the record. It does not replace them: `branch-review` still finds the defects and `branch-cleanup` still tidies.

Whoever uses this skill may not be a seasoned programmer. They can answer a clear question but should not have to remember which step comes next. So the skill stops at each decision that is theirs, says what it will do before doing it, and records each step as it happens. Then neither a later session nor a push can skip a step by accident. Speak the user's language.

## Rules that do not bend

- **The project's and the user's `CLAUDE.md` govern conventions**: branch names, commit style, the language of pull requests, how to run the checks, asking before writing. They never lower the rules in this list. If one clashes with them, stop and ask.
- **Never merge.** Never `rebase`, `reset --hard`, `stash`, `push --force`, delete a branch or skip a hook with `--no-verify`.
- **Never push without a yes.** A push needs the user's yes to that push, in this conversation, given after the pull request body was shown. A request like "make it ready for the PR", "I'm in a hurry" or a yes given in another session is not a yes to the push.
- **Every stamp records a step that just ran.** Each line of the record comes from `code_care_gate.py stamp`, run right after its step and at the commit that step covered. Never write the `state` file by hand. Never stamp a step because the user says it already happened. `stamp checks` runs the checks itself, so "the tests passed this morning" is a reason to run them, not to record them.
- **No fix without a decision.** After the review, nothing is fixed until the user has decided each finding, here or earlier in the conversation.
- **`branch-review` stays read-only.** It reports and writes nothing. This skill writes every stamp and every file in the record folder. `branch-cleanup` makes its own block commits, as it always does. The stamp after it is this skill's.
- **A project-review report is read, never written.** `.review/report.md` belongs to `project-review`. This skill cites its finding numbers and leaves the file as it is.
- **No behaviour change outside a decided fix.** Each fix commit is about one finding. Anything else this skill notices goes to the user, not into a commit.
- **Secrets:** never read out or copy keys, tokens or passwords.
- **No AI signatures** in commits, the pull request body or anywhere else.

Where a step below says to ask something the user has already answered in the conversation, use that answer instead of asking again: decisions on findings, whether to skip the cleanup, whether a development server is open.

## The record

The script is `scripts/code_care_gate.py`, under the base directory the skill tool reported when this skill loaded. Run it with Python 3 from inside the repository: `python3`, `python` or `py -3`, whichever runs Python 3 on this machine. Below it is written as `gate`:

```bash
gate status                       # what is recorded for the current branch, and what a push would be told
gate dir                          # the branch's record folder, inside .git
gate stamp start --kind feature --base <base>
gate stamp review                 # right after branch-review's report, HEAD unchanged
gate stamp fix --finding <n>      # right after each fix commit; report findings as report-<n>
gate stamp cleanup --start <sha>  # right after branch-cleanup; <sha> is where it started
gate stamp cleanup --skipped "<reason>"
gate stamp checks "<command>"     # runs the command, records its exit code, keeps the output in checks.log
```

The record folder (`gate dir`) is inside `.git`, so nothing in it reaches a commit. Besides the script's `state` and `checks.log`, this skill keeps four files there, written with the Write tool:

- `review.md`: the review's numbered findings and its `## Review` section, exactly as `branch-review` gave them, then a `## Decisions` table (step 3).
- `source.md`: only when the input is a `project-review` report (see "Starting from a project-review report").
- `cleanup.md`: the commit the cleanup started from, then `branch-cleanup`'s `## Cleanup` section or the reason it was skipped.
- `pr.md`: the pull request body (step 7).

A stamp and a push never go in the same command. The push gate judges the whole command before it runs, so it would see the record as it was before the stamp. If `git config --get code-care.gate` prints nothing, the gate is off for this clone. Say so once, along with how the user can turn it on (`git config --local code-care.gate ask`), and do not change it yourself. The record works either way.

## 1. Fix the scope and open the record

1. `git branch --show-current`. If it is the default branch or empty (detached HEAD), stop and ask which branch is meant. With a `project-review` report as the input, the fix branch may not exist yet: see that section.
2. `git status --porcelain` must be empty. If it is not, stop and ask: commit the pending work on this branch first (with the user's approval), or cancel. Never `stash`.
3. Find the base the way the siblings do: the one the user names, else what `CLAUDE.md` says, else `git symbolic-ref --short refs/remotes/origin/HEAD`, else `main` or `master`.
4. `gate status`. If something is recorded, go to "Resuming". Otherwise run `gate stamp start --kind feature --base <base>`.
5. Tell the user in two or three sentences: the branch, the base, how many lines the diff has (`git diff --shortstat <merge-base>...HEAD`), and the steps ahead. Say that it will stop after the review for their decisions, and again before pushing.

## 2. Review

Invoke `branch-review` for real, with the skill tool, and name the base. Do not imitate it from memory. The name is an example: a session may list it under a plugin prefix or another name. Match by what its description covers. If no such skill is installed, stop: this skill has no review of its own to fall back on.

When its report is in:

1. Check that `git rev-parse HEAD` is the commit it reviewed and the tree is still clean, then run `gate stamp review`.
2. Write `review.md` in the record folder: a header line with the branch, the base, the merge base and HEAD's short sha, then the report's `## Findings` with their numbers, then the `## Review` section, both copied as given.
3. If there are no findings, say so and go to step 5. Items under "Possible" are not findings: they go into the pull request body as they are.

## 3. Decide: stop here

Show every finding in **one table** with one recommended decision per finding, then stop and wait:

```markdown
| # | Severity | Where | Finding | Verified | Recommended |
|---|---|---|---|---|---|
| 1 | Critical | `src/export.mjs:9` | a scene without a heading vanishes from the export | traced | fix now |
| 2 | Minor | `src/sort.mjs:4` | `part10` may sort before `part2` | would need running | measure first: a test with both names |
```

The decisions are:

- **Fix now:** a commit on this branch (step 4).
- **Measure first:** only for a finding verified as `would need running`. Write the test or run the command that would settle it, report what it showed, and ask again for that finding. A test that confirms the finding becomes that fix's test. One that does not confirm it is deleted by name. Nothing is committed while it is being measured. When only a device or an account the user has can settle it, say what to try there.
- **Defer:** left for later. It goes into the pull request body with the reason.
- **Drop:** not worth fixing, or not a defect after all. It goes into the pull request body with the reason.

Recommend **fix now** for a critical or important finding that was traced or read. Recommend **measure first** for one that would need running, when the project can run what settles it. Recommend **defer** for anything whose fix would reach well outside the branch's files. Ask one question: a decision for each finding, or "as recommended". Then end the turn. Write the answer into `review.md` as a `## Decisions` table (`#`, decision, reason, fix commit) before the first fix.

## 4. Fix, one finding per commit

For each finding decided as "fix now", most severe first:

1. **Write a test that reproduces the scenario**, in the project's test setup. Run it and see it **fail** for the reason the finding gives. If it passes, the finding does not reproduce as written: stop and tell the user before changing any code.
2. **Apply the smallest fix** that makes the scenario come out right. Stay inside the finding's files and its topic.
3. **Run the test again and see it pass**, then the project's fast checks.
4. **Commit the test and the fix together**, alone, with `git add` of their files and a message in the project's style (`git log --oneline -10` shows it), for example `fix(export): keep scenes that have no heading`.
5. In a separate command, `gate stamp fix --finding <n>`. Then fill in the fix commit and the test's name: in `review.md`'s Decisions table for a review finding, or in `source.md`'s table for a report finding, since its fix comes before the review and `review.md` does not exist yet.

If no test can reproduce the finding (only a device can show it), say so before fixing it. Ask whether to fix it without a test, and if so, write "no test: <why>" against it. If a fix makes an earlier check fail, undo it by naming its files (`git restore --staged --worktree -- <file>…`, never `.`) and tell the user. Do not stack a second guess on top. Use a debugging skill such as `systematic-debugging` if investigating is worth it.

**A second review** is worth offering only when the fixes together exceed about 100 changed lines (`git diff --shortstat <review sha>..HEAD`). Fixes that size are new code of their own. Give the price before asking: `branch-review` rereads the whole branch, which costs about 100k tokens on a small diff and more on a larger one. On a yes, invoke it again, `gate stamp review`, add its report to `review.md` as "Second review at <sha>", and take only its new findings through step 3.

## 5. Clean up

Note where the cleanup starts (`git rev-parse HEAD`) at the top of `cleanup.md`, so a later session can find it. Then measure the whole branch: `git diff --shortstat <merge-base>...HEAD`.

- **Under about 150 changed lines**, and above all on a fix branch, a cleanup pass rarely finds anything worth its cost. Offer to skip it. On a yes, run `gate stamp cleanup --skipped "<branch kind> of <n> lines"` and write the reason in `cleanup.md`.
- **Otherwise**, or if the user wants it anyway, invoke `branch-cleanup` for real and name the base. It asks whether the checks passed at HEAD. Answer from step 4: which checks ran after the last fix commit and whether they passed. If no fix was made, the checks have not run on this branch here, so say exactly that. When it wraps up, run `gate stamp cleanup --start <the sha noted above>` and copy its `## Cleanup` section into `cleanup.md`.

## 6. Run the full suite

1. Find the project's real checks, fast and slow, the way the siblings do: `CLAUDE.md`, the project's scripts, the CI configuration. Join them into one command, for example `npm test && npx playwright test`.
2. Before slow end-to-end tests, ask whether a development server is open. Many test runners reuse a server already on their port and would test that instead of the branch.
3. `gate stamp checks "<command>"`. It refuses to run on uncommitted changes, records nothing if HEAD moves meanwhile, prints the last lines and keeps the full output in `checks.log`.
4. If it fails, the branch is not ready. Read the failure in `checks.log`, tell the user which check failed and at which commit, and stop. A test that fails once and passes on a second run is flaky: say so and run the checks again. A fix for a real failure is a new commit after the cleanup, which the gate will list. If it is more than a few lines, offer `branch-cleanup` over it and stamp it as in step 5. If it is a few lines, offer to skip the cleanup for it. On a yes, run `gate stamp cleanup --skipped "fix after the checks, <n> lines"`, so the record covers the new tip, and add the line to `cleanup.md`. Then run the checks again.

## 7. Pull request body, then ask

Write `pr.md` in the record folder, in the language the project uses for pull requests:

```markdown
## Review
- Critical: <finding> (`file:line`), fixed in <short sha>
- Important: <finding> (`file:line`), deferred: <reason>
- Minor: <finding> (`file:line`), dropped: <reason>
- Possible: <item>

## Fixes
- <short sha> <subject>: review finding <n>, test `<test name>`
- <short sha> <subject>: report finding <n> (`.review/report.md`), test `<test name>`

## Cleanup
<branch-cleanup's section as it gave it, or "Skipped: <reason>">
```

Every finding in `## Review` ends with its fate: its fix commit, deferred or dropped. `## Fixes` takes review findings from `review.md`'s Decisions table and report findings from `source.md`'s table. Then show the user `gate status`, the body, and the checks result (command, commit, pass). Then ask one question: push `<branch>` to `<remote>`? On a yes, run `git push -u <remote> <branch>` on its own. If the gate asks or refuses, show what it says. The user's answer to that prompt is the only waiver. Opening the pull request (for example `gh pr create --body-file <record folder>/pr.md`) is another yes. Merging is never this skill's.

## Starting from a project-review report

`project-review` closes with numbered findings grouped into fix branches. When the user points at that report ("fix branch 1 from the report", "findings 2 and 5"):

1. **Read `.review/report.md`** and take the findings by number, with their scenario, files and `Status`. The ones that belong to this branch say "decided for branch <N>". If a finding the user names is deferred, dropped or has no decision yet, ask before taking it on.
2. **The branch.** If the user is on the default branch, say in one line which branch you will create, named the way the project names branches (for example `fix/save-result`), and create it with `git switch -c` from the base. Then go through step 1.
3. **Check each finding still stands.** The report pins each area to a commit. If the lines a finding names changed since (`git diff --stat <its commit> HEAD -- <its files>`), reread them first. A finding already fixed is reported as such, not fixed twice.
4. **Write `source.md`** in the record folder: the report's path and the commit it started at, then a table with one row per finding taken (number, severity, title, files, fix commit, test). The last two columns stay empty until each fix lands.
5. **Fix those findings first**, through step 4's rules, with `gate stamp fix --finding report-<n>`. They were decided at the report's own decision stop, so step 3 is not repeated for them.
6. **Then the normal order**: step 2 reviews the branch, which now holds the fixes, and step 3 covers any new findings from it. Then steps 5, 6 and 7. In `## Fixes`, each report finding is cited by its number and the report's path.
7. **At the close**, tell the user which report findings this branch fixes. Their status in the report becomes "fixed in <PR>" once the branch is merged. That is `project-review`'s to write when it resumes, or the user's. Do not write it.

## Resuming

The record says how far the branch got. Read `gate status` and the files in `gate dir`, check that the tree is clean and the branch is the same one, and continue at the first step not done:

- **A `source.md` whose findings are not all stamped:** compare its findings with the `fix` lines of the record (`report-<n>`). Fix each one still missing through step 4's rules before anything else. The review comes after the report's fixes, so a missing review does not mean those fixes are done, and the push gate does not check fixes.
- **No review recorded**, or one that is no longer part of the branch: step 2.
- **A review, but no `## Decisions` in `review.md`:** show the table again from `review.md` (do not rerun the review) and stop for the decisions.
- **Decisions with "fix now" findings that have no fix stamp:** step 4 for those. A commit after the review that looks like one of those fixes but has no stamp means the step's test was never seen to fail. Ask the user before trusting it. Never stamp it on the commit's word.
- **Commits after the review that are neither stamped fixes nor cleanup blocks:** new code nobody reviewed. Say so and offer the review again.
- **No cleanup recorded:** step 5, starting from the sha in `cleanup.md` if it was noted and `branch-cleanup`'s commits are already on top. Ask if unsure.
- **Checks missing, failed, or recorded at a commit other than the tip:** step 6. An earlier pass at another commit does not cover the tip, whatever anyone remembers.
- **All recorded and complete:** step 7.

Before going on, run the fast checks once. Dependencies or the machine may have changed in between, and a failure that appeared while nobody was working must not be blamed on the next step. Use plain commands here, not `stamp checks`: this run is a warm-up, not the final checks.

## Cost

Most of the cost is the two skills it runs. `branch-review` is about 100k tokens on a small diff. `branch-cleanup` has not been measured, so expect it to cost at least as much on a branch big enough to need it. Measured on small eval branches, a run that reviews, fixes and records came to about 110k to 125k tokens. The fixes, the checks and the record add little beyond the test output, which goes to `checks.log` and is read only at its tail. A second review doubles the review's share, which is why it is offered only above about 100 lines of fixes. On a large branch, say the size before step 2. With a report as input, one fix branch per session keeps each session short, and the record carries the branch from one session to the next.
