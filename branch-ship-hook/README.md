# branch-ship-hook

A record of what happened on a branch (review, fixes, cleanup, checks) and a Claude Code hook that reads it before every `git push`. It catches a forgotten step: a branch pushed without its review, a cleanup that ran before the fixes it should have seen, a commit added after the last check. It is a guard against forgetting, not against someone writing a record by hand.

One file, `code_care_gate.py`, Python 3 standard library only. It is not part of any packaged skill.

## The record

Each branch gets a folder in `<git common dir>/code-care/<branch>/`, inside `.git`, so it never reaches a commit and every worktree of the clone sees the same one. Its `state` file holds one line per step:

```
kind feature
base main
review <sha> <time>
fix <sha> <time> <finding>
cleanup <start sha> <end sha> <time> [skipped <reason>]
checks <sha> <time> pass|fail <exit code> <command>
```

The last line of each kind wins, except `fix`, which adds up. Every stamp reads `HEAD` itself, so it can only record the commit that is checked out:

```bash
python code_care_gate.py stamp start --kind feature --base main
python code_care_gate.py stamp review                     # after branch-review's report
python code_care_gate.py stamp fix --finding 2            # after each fix commit
python code_care_gate.py stamp cleanup --start <sha>      # after branch-cleanup; <sha> is where it started
python code_care_gate.py stamp cleanup --skipped "fix branch of 30 lines"
python code_care_gate.py stamp checks "npm test"          # runs the command and records its exit code
python code_care_gate.py status                           # what is recorded, and what a push would be told
```

`stamp checks` refuses to run with uncommitted changes to tracked files, and records nothing if `HEAD` moves while the checks run. Their full output goes to `checks.log` in the branch's folder.

## What a push needs

For a branch of kind `feature` (the default): a review, a cleanup that started after that review (so it saw the fixes) and ends at the tip, and checks that passed at the tip. For a branch of kind `cleanup`, as `code-cleanup` makes them: the cleanup first, then a review that covers it. Anything after the last covered commit is listed by subject.

The gate never looks at a push of the default branch, a deletion, a push of tags or a dry run, and does nothing in a clone that has not opted in.

## Installing the hook

1. Copy `code_care_gate.py` somewhere stable, for example `~/.claude/hooks/`.
2. Add it to `~/.claude/settings.json`, merging with any hooks already there:

   ```json
   "hooks": {
     "PreToolUse": [
       { "matcher": "Bash", "hooks": [{ "type": "command", "if": "Bash(git *)", "timeout": 10,
           "command": "python3 \"$HOME/.claude/hooks/code_care_gate.py\" gate" }] },
       { "matcher": "PowerShell", "hooks": [{ "type": "command", "if": "PowerShell(git *)", "timeout": 10,
           "command": "python3 \"$HOME/.claude/hooks/code_care_gate.py\" gate" }] }
     ]
   }
   ```

   The `if` filter keeps the script from starting for commands that are not `git`. It is best effort: when Claude Code cannot split a command, the hook runs anyway, and the script looks for the push itself (`cd <dir> && git push`, `git -C <dir> push`, a refspec such as `HEAD:feature`).
3. Opt each clone in:

   ```bash
   git config --local code-care.gate ask
   ```

   With `ask`, an incomplete record turns the push into a permission prompt that says what is missing, and the person decides. With `deny`, Claude Code refuses the push and gives Claude the reason. Leave the setting unset to switch the gate off for that clone.

## Limits

- The hook judges the whole command before it runs, so a stamp and a push in one command are judged with the record as it was: run them separately.
- A timed-out `PreToolUse` hook does not block the tool call, so the script keeps to quick `git` queries. If it fails for any other reason it exits with a non-blocking error and the push goes through the normal permission flow.
- It only sees pushes Claude makes through its shell tools. A person pushing from a terminal, an editor or a desktop client is outside it; a git `pre-push` hook in the repository can read the same `state` file for them.
