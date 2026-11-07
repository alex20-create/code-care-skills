# Report template

Structure of `.review/report.md`. Write it in the user's language, translating the headings too. It is a local working note excluded from git, so a rule that what goes into a repository is written in English does not cover it, unless a `CLAUDE.md` names it.

It is written in two moments:

- **Step 1**, with the map: the summary lines, "Areas" with every area not reached, "Already known", and any secret found in the history under "Findings", as area "none".
- **Step 4**, after each area: that area's row, its findings, possible issues, contracts and what held up.
- **When a fix lands**, on resuming or when the user says so: that finding's status. The finding itself stays as it was written.
- **When the review closes**, if the user wants it closed: the closing section.

```markdown
# Project review: <project> (<date started>)

## Summary
Folder: <path> · started at <commit> (<clean / uncommitted changes present>)
Coverage: <N> of <M> areas reviewed · <K> stale · <J> not reached (a stale area counts as stale, not as reviewed)
Findings: <critical> critical · <important> important · <minor> minor (<n> fixed · <m> fixed, to be confirmed)
Cost: <pass> · estimated <lines> · read <lines> (one entry per pass, so the next estimate starts from real figures)

## Areas
| # | Area | Paths | Lines | Why it ranks here | Status | Commit |
(status: reviewed, reviewed on a dirty tree, stale, skipped — why, not reached)

## Findings
Most severe first. A finding keeps its number once given, even when a later one sorts above it: other notes and branches cite findings by number. Each with:
1. **<Critical | Important | Minor>** · `<file>:<line>` · <one-line title> · area <#, or none>
   Scenario: <trigger → path → result>
   Verified: traced | read | would need running — <what would settle it, and where: a test the project can run, or a device only the user has>
   Fix (not applied): <one line, or "none obvious">
   Status (once fixes land): fixed in <PR or commit> | fixed in <commit>, to be confirmed (until a new pass of its area confirms it) | pending — <deferred, not reproducible, not worth it, undecided>

## Possible
- `<file>:<line>` · <what looks wrong and why it could not be pinned down>

## Contracts to check
- <area #> produces <value> that <area #> consumes: <what to confirm when that area is reviewed>
- ~~<a closed contract>~~ checked in area <#>: holds | became finding <#> | holds except when <state>, joined to <a finding or a possible issue>

## Already known
- <one line each, with where the project records it>

## Looked at and found sound
- <area #>: <two or three lines on what was checked and held up>

## Recommended order
Numbered fix branches, each one root cause or one area, most severe first, each with the files it touches. Then which branches can run side by side (no shared files) and what they still share. Each is separate work, checked with `branch-review` before merging.

## Closing
Closed at <commit> · areas not reviewed: <list, or none> · code the fixes changed since each area's commit: <areas, with lines changed>; those areas are stale for a new pass
```
