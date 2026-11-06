# Report template

Structure of `.cleanup/report.md`. Write it in the user's language, translating the headings too. It is written in two moments:

- **Phase 4**, with the plan: the summary lines known so far (branch, folder), "Blocks" with every block marked pending, "Pending", "Uncertain findings" and "Skills used". Phase 5 updates each block's status as it goes.
- **Phase 6**, at the close: everything else, including "Measurements" and the final review.

Any recommendation that is not a level 3 finding (adding a linter, say) goes under "Pending" as its own group, after the findings.

```markdown
# Cleanup report: <project> (<date>)

## Summary
Branch: <cleanup-branch> · started from <branch> @ <commit>
Folder: <the project's / worktree at <path>>
Blocks applied: X · skipped: Y · reverted: Z
Checks: <same as baseline / improved / what changed>
Flaky tests: <none / which>
Final review: <branch-review over <range>: no findings / N findings, blocks reverted / declined / not installed>

## Measurements
| Measurement | Before | After |
(line count of the main files, build size, tests, linter warnings)

## Blocks
| # | Topic | Status | Commit |

## Pending (deliberately not applied)
Level 3 findings, from most to least severe. Each with: severity (critical, important or minor), fix risk, size, file and lines, and how it was checked (traced, read or would need running). Bugs also carry their failure scenario: trigger → path → wrong result.

### Recommended order
Numbered groups, each meant as separate work on its own branch.

## Decisions taken
What the user decided during the cleanup (skipped blocks, dropped findings) and why.

## Uncertain findings
What looks like a problem but could not be confirmed, and why.

## What could not be checked
Checks that were not run or do not cover something (other browsers, external services, how the app looks...).

## Parked requests
Features or fixes the user asked for during the cleanup, to be done on their own branch.

## Skills used
Installed beforehand and new, and what each one was for.
```
