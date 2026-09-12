---
name: check-in
description: This skill should be used when the user has written code themselves and wants feedback before committing it — e.g. "check my code before I commit", "review this diff for best practices", "is this idiomatic?", "check in on #7 before I ship it" — or says "/check-in". Pre-commit, idiom/convention-focused feedback — distinct from `pr-review` (a finished GitHub PR) and from `git-ship`'s mandatory reviewer gate (acceptance criteria, error handling, test coverage). Advisory only: reports findings, never edits code or blocks anything.
argument-hint: [#N (optional, for ticket/stack context)]
allowed-tools: [Read, Bash(git diff:*), Bash(git status:*), Agent, Glob, Grep]
version: 1.0.0
---

# Check In

Pre-commit feedback on code the *human* just wrote — "tell me what to do better before I commit this." Lightweight and advisory: it reports what a `convention-reviewer` subagent finds and lets the developer decide what to act on. It never edits code and never gates a status transition — that's `git-ship`'s job, not this skill's.

## How this differs from the rest of the review surface
- **`pr-review`** analyzes a finished GitHub PR after the fact, via multiple subagents, and never blocks anything either — but it's a one-time deep pass on a whole PR's diff, not a quick pre-commit check you'd run repeatedly while working.
- **`git-ship`'s reviewer gate** (`ticket-reviewer`, `silent-failure-hunter`, `test-coverage-reviewer`) is mandatory and blocks Ticket Status from reaching `Review` — it checks acceptance criteria, error handling, and test coverage. `check-in` checks none of that; it's purely about whether the code reads the way this language/framework is idiomatically written. Run `check-in` as often as you like; it doesn't replace `git-ship`'s gate and isn't a substitute for it.

## Steps

1. **Gather the diff.** `git diff HEAD` by default (uncommitted changes). If a ticket number was given, note it for context but don't fetch acceptance criteria — that's out of scope here.
2. **Identify the relevant stack** — from `CLAUDE.md`'s Tech Stack table, or, if that doesn't cover what changed, from the changed files' extensions/frameworks directly.
3. **Check for `references/<stack>.md`** (the convention reference `implement-and-tutor` or `/research` may have already built for this stack). If it exists, read it. If it doesn't, proceed anyway — `convention-reviewer` falls back to its own general knowledge, at lower confidence, and will say so.
4. **Launch `convention-reviewer`** against the diff, passing along the reference file's contents if one was found.
5. **Report its findings as-is** — don't editorialize on top of them or silently drop any. If the reviewer flagged something outside its own lane (a pointer to a different reviewer's concern), pass that along too rather than filtering it out.
6. **Don't act on anything automatically.** If the user asks to fix a specific finding, that's a new, explicit request — this skill's own job ends at reporting.

## If there's nothing to review
If `git diff HEAD` is empty, say so and stop — there's nothing to check in on yet.
