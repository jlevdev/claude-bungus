---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git branch:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git log:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh project item-list:*), Bash(gh project item-edit:*), Read, Agent, AskUserQuestion, mcp__github__issue_read
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

3. **Reviewer gate (only for a ticket not already past it).** This is what closes the gap for tickets built outside `implement`'s own TDD loop (e.g. via `implement-and-tutor`, or any ticket someone just wrote code for by hand) — `implement` already runs this gate itself before it sets Ticket Status to `Review`, so re-running it here would just be redundant work on the same diff.
   - Resolve the ticket's project item (`gh project item-list <number> --owner <owner> --format json`, matching on the issue's URL) and check its current Ticket Status.
   - **If Ticket Status is already `Review` or `Done`:** this ticket already passed the gate — skip to step 4.
   - **Otherwise:** fetch the issue body via `issue_read`, then launch the `ticket-reviewer`, `silent-failure-hunter`, and `test-coverage-reviewer` subagents in parallel against the diff from the Context section above, giving each the issue number and its `issue_read` contents. Same verdict handling as `implement`'s reviewer gate: `ticket-reviewer`/`test-coverage-reviewer` output `BLOCKED` or `PASS`; `silent-failure-hunter` blocks only on `CRITICAL`. If any agent blocks, fix it and **re-run all three** against the updated diff, not just the one that flagged. Once all three are non-blocking, carry their non-blocking notes forward to report to the user alongside the PR URL in step 7.
   - Once clean, set the ticket's Ticket Status to `Review`. **Same hook constraint as `implement`:** `require-tests-before-review.sh` is a `PreToolUse` hook that inspects the `gh project item-edit` command's literal text before bash evaluates anything — the project id, Ticket Status field id, and status option id (from `.claude/github-project-config.json`) must be typed directly into the command as real values, never as a shell variable or `$(...)` substitution, or the hook can't see what it's matching on:
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
