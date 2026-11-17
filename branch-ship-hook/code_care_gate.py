#!/usr/bin/env python3
"""Record the review, cleanup and checks of a branch, and gate pushes on them.

Usage:
  code_care_gate.py gate                      PreToolUse hook: reads the hook's JSON on stdin
  code_care_gate.py stamp start [--kind feature|cleanup] [--base <branch>]
  code_care_gate.py stamp review
  code_care_gate.py stamp fix [--finding <n>]
  code_care_gate.py stamp cleanup --start <sha>
  code_care_gate.py stamp cleanup --skipped "<reason>"
  code_care_gate.py stamp checks "<command>"  runs the command and records its exit code
  code_care_gate.py status [<branch>]         what is recorded, and what a push would be told
  code_care_gate.py dir [<branch>]            the branch's record folder

Every stamp reads HEAD itself, so it can only record the commit that is checked out.
The record lives in <git common dir>/code-care/<branch>/state, inside .git, so it never
reaches a commit and every worktree of the clone sees it. It guards against forgetting
a step, not against someone writing a stamp by hand.

The gate does nothing in a clone that has not opted in:
  git config --local code-care.gate ask     (or deny)
It never gates the default branch, a deletion, tags, or a dry run.
Standard library only.
"""

import datetime
import json
import os
import re
import shlex
import subprocess
import sys

STATE_FILE = "state"
UNSAFE = re.compile(r'[<>:"|?*\\]')


# ---------------------------------------------------------------- git helpers

def git(repo, *args):
    """Run git in repo; return (exit code, stripped stdout)."""
    try:
        done = subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except OSError:
        return 1, ""
    return done.returncode, done.stdout.strip()


def toplevel(path):
    if not path or not os.path.isdir(path):
        return None
    code, out = git(path, "rev-parse", "--show-toplevel")
    return out if code == 0 and out else None


def common_dir(repo):
    code, out = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if code != 0 or not out:
        raise SystemExit("not a git repository: " + repo)
    return out


def head(repo):
    code, out = git(repo, "rev-parse", "HEAD")
    if code != 0:
        raise SystemExit("the repository has no commits yet")
    return out


def current_branch(repo):
    code, out = git(repo, "branch", "--show-current")
    return out if code == 0 else ""


def branch_tip(repo, branch):
    code, out = git(repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch)
    return out if code == 0 and out else None


def is_ancestor(repo, older, newer):
    code, _ = git(repo, "merge-base", "--is-ancestor", older, newer)
    return code == 0


def commits_between(repo, older, newer):
    code, out = git(repo, "log", "--format=%h %s", older + ".." + newer)
    return out.splitlines() if code == 0 and out else []


def default_branch(repo):
    code, out = git(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if code == 0 and "/" in out:
        return out.split("/", 1)[1]
    for name in ("main", "master"):
        if branch_tip(repo, name):
            return name
    return None


def tracked_changes(repo):
    code, out = git(repo, "status", "--porcelain", "--untracked-files=no")
    return out if code == 0 else ""


def short(sha):
    return sha[:7] if sha else "-"


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="minutes")


# ---------------------------------------------------------------- the record

def record_dir(repo, branch):
    safe = "/".join(UNSAFE.sub("_", part) for part in branch.split("/"))
    return os.path.normpath(os.path.join(common_dir(repo), "code-care", *safe.split("/")))


def read_state(repo, branch):
    """Last line of each kind wins, except fixes, which add up."""
    state = {"kind": "feature", "base": None, "review": None, "fixes": [],
             "cleanup": None, "checks": None}
    path = os.path.join(record_dir(repo, branch), STATE_FILE)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split(" ")
            key = parts[0]
            if key == "kind" and len(parts) > 1:
                state["kind"] = parts[1]
            elif key == "base" and len(parts) > 1:
                state["base"] = parts[1]
            elif key == "review" and len(parts) > 1:
                state["review"] = parts[1]
            elif key == "fix" and len(parts) > 1:
                state["fixes"].append({"sha": parts[1],
                                       "finding": parts[3] if len(parts) > 3 else "-"})
            elif key == "cleanup" and len(parts) > 2:
                state["cleanup"] = {"start": parts[1], "end": parts[2],
                                    "skipped": " ".join(parts[5:]) if parts[4:5] == ["skipped"] else None}
            elif key == "checks" and len(parts) > 4:
                state["checks"] = {"sha": parts[1], "result": parts[3],
                                   "exit": parts[4], "command": " ".join(parts[5:])}
    return state


def append(repo, branch, line):
    folder = record_dir(repo, branch)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, STATE_FILE), "a", encoding="utf-8", newline="\n") as handle:
        handle.write(line + "\n")


def evaluate(repo, branch, tip):
    """Everything a push of this tip would be told. Empty means complete."""
    state = read_state(repo, branch)
    if state is None:
        return ["no review, cleanup or checks recorded for this branch"]
    problems = []
    kind = state["kind"]
    review, cleanup, checks = state["review"], state["cleanup"], state["checks"]

    if not review:
        problems.append("review: not recorded")
    elif not is_ancestor(repo, review, tip):
        problems.append("review: recorded at %s, which is no longer part of the branch" % short(review))
        review = None
    if not cleanup:
        problems.append("cleanup: not recorded")
    elif not is_ancestor(repo, cleanup["end"], tip):
        problems.append("cleanup: recorded up to %s, which is no longer part of the branch" % short(cleanup["end"]))
        cleanup = None

    if review and cleanup:
        if kind == "cleanup":
            if not is_ancestor(repo, cleanup["end"], review):
                problems.append("review at %s ran before the cleanup ended at %s"
                                % (short(review), short(cleanup["end"])))
        elif not cleanup["skipped"] and not is_ancestor(repo, review, cleanup["start"]):
            problems.append("cleanup started at %s, before the review at %s: it has not seen the fixes"
                            % (short(cleanup["start"]), short(review)))

    covered = review if kind == "cleanup" else (cleanup["end"] if cleanup else None)
    if covered and covered != tip:
        later = commits_between(repo, covered, tip)
        if later:
            what = "review" if kind == "cleanup" else "cleanup"
            listed = "; ".join(later[:3]) + ("; ..." if len(later) > 3 else "")
            problems.append("%d commit(s) after the %s: %s" % (len(later), what, listed))

    if not checks:
        problems.append("checks: not recorded")
    elif checks["sha"] != tip:
        problems.append("checks: last run at %s, not at the tip %s" % (short(checks["sha"]), short(tip)))
    elif checks["result"] != "pass":
        problems.append("checks: failed at the tip (exit %s)" % checks["exit"])
    return problems


# ---------------------------------------------------------------- stamp

def stamp(args):
    repo = toplevel(os.getcwd())
    if not repo:
        raise SystemExit("run it inside a git repository")
    branch = current_branch(repo)
    if not branch:
        raise SystemExit("not on a branch (detached HEAD): nothing to record")
    if not args:
        raise SystemExit("stamp what? start, review, fix, cleanup or checks")
    step, rest = args[0], args[1:]
    sha = head(repo)

    def option(name):
        if name in rest:
            at = rest.index(name)
            if at + 1 < len(rest):
                return rest[at + 1]
            raise SystemExit(name + " needs a value")
        return None

    if step == "start":
        kind = option("--kind") or "feature"
        if kind not in ("feature", "cleanup"):
            raise SystemExit("--kind is feature or cleanup")
        append(repo, branch, "kind " + kind)
        base = option("--base")
        if base:
            append(repo, branch, "base " + base)
        print("recorded: %s is a %s branch%s" % (branch, kind, " on " + base if base else ""))
    elif step == "review":
        append(repo, branch, "review %s %s" % (sha, now()))
        print("recorded: review of %s at %s" % (branch, short(sha)))
    elif step == "fix":
        finding = option("--finding") or "-"
        append(repo, branch, "fix %s %s %s" % (sha, now(), finding))
        print("recorded: fix at %s (finding %s)" % (short(sha), finding))
    elif step == "cleanup":
        skipped = option("--skipped")
        start = option("--start")
        if skipped:
            append(repo, branch, "cleanup %s %s %s skipped %s" % (sha, sha, now(), skipped))
            print("recorded: cleanup skipped at %s (%s)" % (short(sha), skipped))
        elif start:
            code, full = git(repo, "rev-parse", "--verify", "--quiet", start + "^{commit}")
            if code != 0 or not full:
                raise SystemExit("unknown commit: " + start)
            if not is_ancestor(repo, full, sha):
                raise SystemExit("%s is not an ancestor of HEAD" % start)
            append(repo, branch, "cleanup %s %s %s" % (full, sha, now()))
            print("recorded: cleanup %s..%s" % (short(full), short(sha)))
        else:
            raise SystemExit('stamp cleanup needs --start <sha> or --skipped "<reason>"')
    elif step == "checks":
        if len(rest) != 1:
            raise SystemExit('stamp checks takes the command as one quoted string')
        if tracked_changes(repo):
            raise SystemExit("tracked files have uncommitted changes: the checks would not be checking HEAD")
        command = rest[0]
        folder = record_dir(repo, branch)
        os.makedirs(folder, exist_ok=True)
        log_path = os.path.join(folder, "checks.log")
        with open(log_path, "w", encoding="utf-8", errors="replace") as log:
            code = subprocess.run(command, shell=True, cwd=repo, stdout=log,
                                  stderr=subprocess.STDOUT).returncode
        if head(repo) != sha:
            raise SystemExit("HEAD moved while the checks ran: nothing recorded")
        result = "pass" if code == 0 else "fail"
        append(repo, branch, "checks %s %s %s %d %s" % (sha, now(), result, code, command))
        with open(log_path, encoding="utf-8", errors="replace") as log:
            tail = log.read().splitlines()[-15:]
        print("\n".join(tail))
        print("recorded: checks %s at %s (exit %d); full output in %s" % (result, short(sha), code, log_path))
        sys.exit(code)
    else:
        raise SystemExit("unknown step: " + step)


# ---------------------------------------------------------------- status and dir

def status(args):
    repo = toplevel(os.getcwd())
    if not repo:
        raise SystemExit("run it inside a git repository")
    branch = args[0] if args else current_branch(repo)
    if not branch:
        raise SystemExit("not on a branch: name one")
    tip = branch_tip(repo, branch)
    if not tip:
        raise SystemExit("no local branch named " + branch)
    state = read_state(repo, branch)
    print("branch %s, tip %s" % (branch, short(tip)))
    if state:
        print("  kind:    %s%s" % (state["kind"], ", base " + state["base"] if state["base"] else ""))
        print("  review:  %s" % short(state["review"]))
        if state["fixes"]:
            print("  fixes:   %s" % ", ".join("%s (finding %s)" % (short(f["sha"]), f["finding"])
                                            for f in state["fixes"]))
        cleanup = state["cleanup"]
        if cleanup:
            print("  cleanup: %s" % ("skipped at %s (%s)" % (short(cleanup["end"]), cleanup["skipped"])
                                    if cleanup["skipped"] else
                                    "%s..%s" % (short(cleanup["start"]), short(cleanup["end"]))))
        else:
            print("  cleanup: -")
        checks = state["checks"]
        print("  checks:  %s" % ("%s at %s (%s)" % (checks["result"], short(checks["sha"]), checks["command"])
                                if checks else "-"))
    # Say what the gate would do with a push of this branch, by the same rules gate() applies.
    if branch == default_branch(repo):
        print("  push:    not gated (default branch)")
        return
    problems = evaluate(repo, branch, tip)
    _, mode = git(repo, "config", "--get", "code-care.gate")
    if mode not in ("ask", "deny"):
        print("  push:    not gated (code-care.gate is off in this clone); record "
              + ("complete" if not problems else "missing: " + "; ".join(problems)))
        return
    verb = "would refuse: " if mode == "deny" else "would ask: "
    print("  push:    " + ("complete" if not problems else verb + "; ".join(problems)))


def show_dir(args):
    repo = toplevel(os.getcwd())
    if not repo:
        raise SystemExit("run it inside a git repository")
    branch = args[0] if args else current_branch(repo)
    if not branch:
        raise SystemExit("not on a branch: name one")
    print(record_dir(repo, branch))


# ---------------------------------------------------------------- gate

SEPARATORS = re.compile(r"&&|\|\||[;|\n&]")
GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
PUSH_WITH_VALUE = {"--repo", "-o", "--push-option", "--receive-pack", "--exec"}


def tokens_of(segment, powershell):
    try:
        if powershell:
            return [t[1:-1] if len(t) > 1 and t[0] == t[-1] and t[0] in "'\"" else t
                    for t in shlex.split(segment, posix=False)]
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def native(path):
    """Git Bash writes C:\\x as /c/x; Python on Windows needs the drive back."""
    if os.name == "nt":
        match = re.match(r"^/([a-zA-Z])(/.*)?$", path)
        if match:
            return match.group(1).upper() + ":" + (match.group(2) or "/")
    return path


def moved(folder, target):
    target = native(os.path.expanduser(target))
    return target if os.path.isabs(target) else os.path.join(folder, target)


def find_pushes(command, cwd, powershell):
    """Each `git push` in the command, with the folder it runs in and its arguments."""
    pushes = []
    folder = native(cwd)
    for segment in SEPARATORS.split(command):
        tokens = tokens_of(segment.strip(), powershell)
        while tokens and (tokens[0] == "&" or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0])):
            tokens = tokens[1:]
        if not tokens:
            continue
        first = os.path.basename(tokens[0]).lower()
        if first in ("cd", "set-location", "pushd", "sl") and len(tokens) > 1:
            folder = moved(folder, tokens[-1])
            continue
        if first not in ("git", "git.exe"):
            continue
        here, i = folder, 1
        while i < len(tokens) and tokens[i].startswith("-"):
            flag = tokens[i]
            if flag == "-C" and i + 1 < len(tokens):
                here = moved(here, tokens[i + 1])
                i += 2
            elif flag in GLOBAL_WITH_VALUE:
                i += 2
            else:
                i += 1
        if i < len(tokens) and tokens[i] == "push":
            pushes.append((here, tokens[i + 1:]))
    return pushes


def pushed_branches(repo, args):
    flags, positionals, i = set(), [], 0
    while i < len(args):
        arg = args[i]
        if arg in PUSH_WITH_VALUE:
            i += 2
            continue
        if arg.startswith("-"):
            flags.add(arg.split("=", 1)[0])
        else:
            positionals.append(arg)
        i += 1
    if flags & {"--dry-run", "-n", "--delete", "-d"}:
        return []
    if flags & {"--all", "--branches", "--mirror"}:
        code, out = git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads")
        return out.splitlines() if code == 0 else []
    refspecs = positionals[1:]
    current = current_branch(repo)
    if not refspecs:
        return [] if "--tags" in flags or not current else [current]
    branches = []
    for spec in refspecs:
        source = spec.lstrip("+").split(":", 1)[0]
        if not source:
            continue
        if source == "HEAD":
            source = current
        if source.startswith("refs/heads/"):
            source = source[len("refs/heads/"):]
        if source and branch_tip(repo, source):
            branches.append(source)
    return branches


def gate():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    tool = data.get("tool_name", "")
    if tool not in ("Bash", "PowerShell"):
        return 0
    command = (data.get("tool_input") or {}).get("command", "") or ""
    if "push" not in command:
        return 0
    cwd = data.get("cwd") or os.getcwd()
    findings, strict = [], False
    for folder, args in find_pushes(command, cwd, tool == "PowerShell"):
        repo = toplevel(folder)
        if not repo:
            continue
        _, mode = git(repo, "config", "--get", "code-care.gate")
        if mode not in ("ask", "deny"):
            continue
        default = default_branch(repo)
        for branch in pushed_branches(repo, args):
            if branch == default:
                continue
            tip = branch_tip(repo, branch)
            problems = evaluate(repo, branch, tip) if tip else []
            if problems:
                findings.append("%s (%s): %s" % (branch, os.path.basename(repo), "; ".join(problems)))
                strict = strict or mode == "deny"
    if not findings:
        return 0
    reason = ("code-care gate. " + " | ".join(findings) +
              ". Record the missing steps with code_care_gate.py stamp, or push anyway if that is meant.")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny" if strict else "ask",
        "permissionDecisionReason": reason,
    }}))
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    command, rest = argv[0], argv[1:]
    if command == "gate":
        try:
            return gate()
        except SystemExit as stop:
            print("code-care gate: %s" % stop, file=sys.stderr)
            return 1
        except Exception as error:  # a broken gate must not block every command
            print("code-care gate failed: %s" % error, file=sys.stderr)
            return 1
    if command == "stamp":
        stamp(rest)
        return 0
    if command == "status":
        status(rest)
        return 0
    if command == "dir":
        show_dir(rest)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
