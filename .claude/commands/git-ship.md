---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git branch:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git log:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh project item-list:*), Bash(gh project item-edit:*), Bash(gh issue view:*), Bash(gh issue comment:*), Read, Agent, AskUserQuestion, mcp__github__issue_read
description: Commit, push, and open a PR in one step — gates on the reviewer subagents and moves Ticket Status to Review for any ticket that hasn't already passed that gate
---

## Context
- Current branch: !`git branch --show-current`
- Git status: !`git status`
- Staged and unstaged changes: !`git diff HEAD`

## When to use
Use this instead of running `/git-branch`, `/git-commit` (agent-only — see below), and `/git-pr` separately when a ticket is fully implemented, tested, and ready to ship in one motion. For incremental commits during development, no command is needed — a plain `git commit` covers that; don't open a PR before the ticket is actually done.

## Steps

1. If the context above shows the current branch is `main` (or the repository's default branch per `CLAUDE.md`), create a feature branch first, following the `/git-branch` naming conventions. If the branch type/slug isn't obvious from context, ask.

2. **Resolve the ticket, if any.** Parse an issue number out of the branch name (`feat/<N>-<slug>` / `fix/<N>-<slug>`). If the branch doesn't match that shape (e.g. a `chore/` branch with no ticket), skip straight to step 4 — there's no acceptance criteria to gate against.

3. **Reviewer gate — skipped only for a ticket that already passed it against this exact diff; runs otherwise.** This is what closes the gap for tickets built outside `implement`'s own TDD loop (e.g. via `implement-and-tutor`, or any ticket someone just wrote code for by hand) — `implement` already runs this gate itself before it sets Ticket Status to `Review`, so re-running it here would just be redundant work on the same diff.
   - **Resolve the ticket's project item.** Read `.claude/github-project-config.json` for `project.number` and `project.owner`, then `gh project item-list <project.number> --owner <project.owner> --limit 200 --format json` (the default limit is 30 — set it high enough to actually cover the whole board) and match the single item whose content URL equals this issue's URL. If none match or more than one does, stop and report rather than guessing which item this ticket is. Check that item's current Ticket Status.
   - **Compute the current diff's fingerprint** (needed either way — to compare against, or to record): regenerate it live, don't reuse the Context section's snapshot, and diff against the branch's merge-base with the repository's default branch — not `HEAD`. `git diff HEAD` only shows uncommitted changes, but this project's own conventions (see "When to use" above) allow plain `git commit`s during development, so by the time `git-ship` runs, some or all of a ticket's real changes may already be committed — a `HEAD`-based diff would miss them entirely, and the reviewer gate would trivially pass on whatever little or nothing is left uncommitted. Diffing against the merge-base instead captures every change this branch has made since it diverged, committed or not, and — as a side effect — keeps the fingerprint stable across step 4's own commit (the merge-base point doesn't move; `HEAD` does). Untracked files still need adding separately (`git diff` never includes those), read safely — filenames aren't shell-escaped, so this must never pass one through a shell string:
     ```bash
     set -euo pipefail
     merge_base=$(git merge-base HEAD <default-branch>)
     {
       git diff --binary "$merge_base";
       git ls-files --others --exclude-standard -z | while IFS= read -r -d '' path; do
         if [ -f "$path" ] && [ ! -L "$path" ]; then
           printf '%s\n' "--- new file: $path ---"
           cat -- "$path"
         else
           printf '%s\n' "--- skipped non-regular-file path: $path ---"
         fi
       done
     } | sha256sum | cut -d" " -f1
     ```
     `set -euo pipefail` matters here, not just as habit: without it, a failed `git merge-base` (detached HEAD, missing default-branch ref, etc.) would silently pass an empty revision to `git diff`, and the pipeline would still produce *some* hash rather than erroring — a fingerprint computed this way could coincidentally match an equally-broken prior marker and wrongly skip the gate. Skipping symlinks/special files (instead of `cat`-ing them) avoids the same fate from a different cause: `cat` on a symlink to `/dev/zero` or an unread FIFO never returns, hanging this step indefinitely on a single stray untracked file.
   - **If Ticket Status is already `Review` or `Done`:** look up the ticket's most recent fingerprint marker — `gh issue view <N> --json comments --jq` for the latest comment matching `<!-- reviewed-diff-sha256: ... -->`. If it matches the fingerprint just computed, this exact diff already passed the gate — skip to step 4. If it doesn't match (or no marker exists — a ticket reviewed before this mechanism existed), something changed since the last review despite the status still saying `Review`/`Done`; fall through and run the gate below, same as if status were still `In Progress`.
   - **Otherwise (gate not yet passed, or the diff changed since it last did):** fetch the issue body via `issue_read`, then launch the `ticket-reviewer`, `silent-failure-hunter`, and `test-coverage-reviewer` subagents in parallel against the diff just computed above, giving each the issue number and its `issue_read` contents. Same verdict handling as `implement`'s reviewer gate: `ticket-reviewer`/`test-coverage-reviewer` output `BLOCKED` or `PASS`; `silent-failure-hunter` blocks only on `CRITICAL`. If any agent blocks, fix it, **recompute the fingerprint fresh** (the files just changed), and **re-run all three** against the new diff, not just the one that flagged. Once all three are non-blocking, carry their non-blocking notes forward to report to the user alongside the PR URL in step 7.
   - Once clean, record the fingerprint so a future `git-ship` call can trust this result:
     ```bash
     gh issue comment <N> --body "Reviewer gate passed for <fingerprint>.
     <!-- reviewed-diff-sha256: <fingerprint> -->"
     ```
     Then set the ticket's Ticket Status to `Review`. **Same hook constraint as `implement`:** `require-tests-before-review.sh` is a `PreToolUse` hook that inspects the `gh project item-edit` command's literal text before bash evaluates anything — the project id, Ticket Status field id, and status option id (from `.claude/github-project-config.json`) must be typed directly into the command as real values, never as a shell variable or `$(...)` substitution, or the hook can't see what it's matching on:
     ```bash
     gh project item-edit --id <item-id> --project-id <project id> --field-id <ticket status field id> --single-select-option-id <status option id>
     ```

4. Stage and commit following `git-commit`'s conventions (conventional commit format, ticket ID reference, its safety checks — never stage `.env`/secrets, flag unrelated changes). `git-commit` is agent-only (`user-invocable: false`) precisely so this is the only place besides `implement` that follows those conventions — you never type it directly.
5. Push the branch: `git push -u origin <branch>`.
6. Open a PR using the `/git-pr` template and conventions.
7. Report the PR URL, plus any Reviewer Notes carried forward from step 3.

## Safety
- Never push directly to `main`/`master` — always via a branch and PR. The `git-safety.sh` hook already blocks this at the tool-call level; if it fires, that's a signal to branch properly, not a bug to route around (e.g. by force-pushing or a refspec trick).
- Confirm with the user before force-pushing under any circumstance.
- If `scan-commit-diff.sh` blocks the commit step, resolve that before continuing — do not skip straight to push.
- Make sure the full test suite genuinely passes before setting Ticket Status to `Review` in step 3 — the hook re-verifies, but shouldn't be the first line of defense.
