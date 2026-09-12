---
name: implement
description: This skill should be used when the user asks to implement, build, or work on one or more tickets — e.g. "implement #12", "build #7", "let's start on #4 and #5" — or says "/implement". Enters test-driven implementation mode against this project's GitHub Issues + Projects ticket workflow.
argument-hint: <#N> [more issue numbers...]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, EnterWorktree, ExitWorktree, mcp__github__issue_read, mcp__github__issue_write, mcp__github__list_issues, mcp__github__search_issues, mcp__github__add_issue_comment, mcp__github__projects_get, mcp__github__projects_list]
version: 2.3.1
---

# Implement Mode

Build one or more tickets using test-driven development. Tickets are GitHub Issues on this repo's GitHub Project — see `CLAUDE.md`'s "Ticket System" section for the field schema (Ticket Status, `type:*`/`priority:*`/`effort:*` labels, native Milestone).

**Ticket Status changes go through `gh project item-edit` (Bash), not the MCP `projects_write` tool.** It's a deterministic single-field flip, the same category of operation `wrap-up` already does via `gh`, and — unlike an MCP call — a Bash command is what `require-tests-before-review.sh` can actually see and gate on before a ticket reaches `Review`.

**The field/option ids must appear as literal values in the command itself — never as a shell variable or a `$(...)` substitution.** `require-tests-before-review.sh` is a `PreToolUse` hook: it inspects the command's *text* before bash evaluates anything, so `--field-id "$FIELD_ID"` or `--field-id "$(jq ...)"` never actually contains the resolved id string the hook is matching on — the gate would silently pass through every Review transition instead of enforcing anything. Resolve the ids first, as their own step (`Read` the file, or a `cat .claude/github-project-config.json` Bash call whose output you read back), then write the `gh project item-edit` command with the real values typed directly in:
```bash
gh project item-edit --id <item-id> --project-id <project id> --field-id <ticket status field id> --single-select-option-id <status option id>
```
substituting the actual values from `.claude/github-project-config.json` (written by `/bg:init`) for every placeholder above — not the placeholder text, and not a reference to where it came from. `<item-id>` is the project item id for this ticket's issue — resolve it by reading `.claude/github-project-config.json` for `project.number`/`project.owner`, then `gh project item-list <project.number> --owner <project.owner> --limit 200 --format json` (the default limit is 30 — set it high enough to actually cover the whole board) and matching the single item whose content URL equals this issue's URL; if none match or more than one does, stop and report rather than guessing which item this ticket is. Skip this if the item-id is already known from an earlier step this run.

## Pre-flight

1. Read `CLAUDE.md` — tech stack, conventions, constraints.
2. Read `PRD.md` — full project context and requirements.
3. Locate each referenced ticket via `issue_read` (by issue number). If a number doesn't resolve to an issue, say so and stop rather than guessing which one was meant.
4. Check for blocking open questions: `search_issues` for open issues labeled `type:question` whose body's `## Blocks` section references this ticket's number. If any exist, surface them to the user and stop — do not begin implementation until they are answered (closed) or explicitly waived.
5. **Worktree isolation (opt-in).** Check whether the session is already inside a *linked* worktree via git's own metadata, not a path guess — `git rev-parse --git-dir` and `git rev-parse --git-common-dir` are equal in a normal checkout and differ in any linked worktree, regardless of where it lives on disk:
   ```bash
   [[ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]] && echo "already in a worktree"
   ```
   If already in one, skip this step entirely — don't nest. Otherwise ask via `AskUserQuestion`: *"Implement this in an isolated git worktree?"* — `No, use the current working tree` (recommended default) / `Yes, isolate in a worktree`. If yes:
   - Call `EnterWorktree` with `name` set to the ticket number (or first ticket number, if several — e.g. `12`).
   - `EnterWorktree` always names the branch `worktree-<name>`, which doesn't match this project's `feat/<N>-<slug>` / `fix/<N>-<slug>` convention (see `git-branch.md`) — rename it to match. The prefix comes from the issue's `type:` label (`type:feature` → `feat/`, anything else → `fix/`); the slug is a short kebab-case version of the issue title. Target name: `<feat-or-fix>/<N>-<slug>` — e.g. issue #12 "User auth" labeled `type:feature` → `feat/12-user-auth`.
     - **Check the target name doesn't already exist first** — `git show-ref --verify --quiet refs/heads/<target>`. If it does, a branch with that name predates this workflow run; **don't rename at all**, stay on `worktree-<name>`, and just note this to the user (not worth a blocking `AskUserQuestion` for what should be a rare collision, but silent behavior divergence isn't OK either). This matters more than it sounds like: verified live that `git branch -m` onto an existing name fails (exit 128) rather than overwriting anything, but the closing step below deletes whatever name it's holding on `remove` — if it held the target name despite the rename never happening, it would delete a pre-existing branch this workflow never touched.
     - Only if the target didn't already exist: run the rename (`git branch -m <target>`) and remember `<target>` for the closing step. If the rename itself unexpectedly fails despite the pre-check (race with something else touching branches concurrently), fall back to the no-rename path above rather than remembering a name that was never actually applied.

   Everything from here on — file moves, edits, tests, the reviewer-gate subagents in step 6 below, git commands — runs inside that worktree automatically, since it's a session-level directory switch, not something each step has to account for separately. This reduces the blast radius of a bad TDD cycle to a disposable branch instead of the working tree the user is actually looking at. Ask once per invocation, covering every ticket in this batch together, not per ticket.
6. Set each target ticket's Ticket Status to `In Progress` via `gh project item-edit` (see above).
7. Scan existing source code to understand current patterns, naming conventions, and architecture.

## Implementation rules

- **TDD first:** write failing tests before writing implementation code. No exceptions.
- Work one ticket at a time unless tickets are explicitly independent and non-overlapping.
- If a genuine blocker is hit mid-implementation (ambiguous requirement, missing dependency, conflicting spec) that cannot be reasonably inferred: open a GitHub issue labeled `type:question` using `templates/question.md`'s structure via `issue_write`, note which ticket it blocks in the `## Blocks` section, stop work on that ticket, and report to the user. Do not guess an answer that could require significant rework.
- Do not refactor unrelated code. Stay in scope.
- Follow the tech stack and conventions from `CLAUDE.md` exactly.

## TDD workflow per ticket

1. Read the ticket's acceptance criteria and "Test Coverage Required" section (from the issue body via `issue_read`).
2. Write tests for each criterion — they must fail at this point.
3. Implement the minimum code to make the tests pass.
4. Confirm tests pass.
5. Refactor only within the scope of this ticket, keeping tests green.
6. **Reviewer gate:** launch the `ticket-reviewer`, `silent-failure-hunter`, and `test-coverage-reviewer` subagents in parallel against this ticket's diff, giving each the issue number and its `issue_read` contents (they don't have their own MCP access to re-fetch it). Each has its own verdict vocabulary — `ticket-reviewer`/`test-coverage-reviewer` output `BLOCKED` or `PASS`; `silent-failure-hunter` blocks only on a `CRITICAL` finding. Treat any of those (`BLOCKED` or `CRITICAL`) as blocking. If any agent blocks, fix it and **re-run all three agents** against the updated diff, not just the one that flagged — a fix for one agent's finding can introduce something a different agent would have caught. Proceed to step 7 only once all three are non-blocking. Carry every non-blocking note forward into step 9 under "Reviewer Notes" so the human reviewer sees them without re-running the same checks.
7. **Record the reviewed diff's fingerprint**, so a later `git-ship` call can tell whether anything has changed since this gate passed: compute it the same way `git-ship` does — diffed against the branch's merge-base with the default branch (not `HEAD`, which only shows uncommitted changes and would miss anything already committed), plus the full contents of every untracked file read safely (no filename ever passed through a shell string), concatenated and hashed:
   ```bash
   merge_base=$(git merge-base HEAD <default-branch>)
   {
     git diff --binary "$merge_base";
     git ls-files --others --exclude-standard -z | while IFS= read -r -d '' path; do
       printf '%s\n' "--- new file: $path ---"
       cat -- "$path"
     done
   } | sha256sum | cut -d" " -f1
   ```
   Post it via `add_issue_comment`, with a body of the form:
   ```
   Reviewer gate passed for <fingerprint>.
   <!-- reviewed-diff-sha256: <fingerprint> -->
   ```
   Then set the ticket's Ticket Status to `Review` via `gh project item-edit` (see above) — this is what `require-tests-before-review.sh` gates on, so make sure the full test suite genuinely passes first; the hook re-verifies but shouldn't be the first line of defense.
8. **If, and only if,** this ticket involved a genuine architectural or approach decision that isn't obvious from reading the resulting code and isn't already covered by an existing `DECISIONS.md` entry (e.g. "chose polling over a websocket for v1," "denormalized X for read performance") — not something ambiguous enough to have warranted a blocking question, but still worth a future reader knowing *why* the code is shaped this way: draft an ADR entry using the template in `DECISIONS.md` (skip entirely if `DECISIONS.md` doesn't exist yet at the project root — don't create it here, that's `start-project`'s job) and ask via `AskUserQuestion` (`Add to DECISIONS.md` / `Skip` / `Edit first`) before appending. Most tickets won't produce one of these — don't manufacture a decision to fill this step.
9. Summarize: what files changed, what tests were added, any decisions made (including whether one was recorded to `DECISIONS.md`), and the Reviewer Notes from step 6.

## When all requested tickets are finished

- Confirm the full test suite still passes.
- List all tickets moved to `Review`.
- Note any follow-on work or new remediation items discovered during implementation (open them as GitHub issues with Ticket Status `Todo` if warranted).
- **If this session entered a worktree in Pre-flight step 5**, ask via `AskUserQuestion`: *"Keep the worktree (review/push/PR from there — recommended) or remove it?"* — then call `ExitWorktree` with `action: "keep"` or `action: "remove"` accordingly (`remove` needs `discard_changes: true` if anything's uncommitted; confirm that's really wanted before passing it — it deletes the branch). Either way this returns the session to the original working tree.
  - **On `remove`, if and only if step 5 actually renamed the branch** (a remembered `<target>` name exists — not just attempted, actually succeeded), also explicitly delete it — `git branch -D <target>`. Verified this is actually needed, not just cautious: `ExitWorktree`'s own cleanup only reaches the branch under the `worktree-<name>` name it originally created, so after a successful rename it silently leaves the renamed branch behind on disk. `ExitWorktree` still removes the worktree directory itself correctly either way — it's specifically the now-orphaned branch that needs this extra step. If step 5 skipped the rename (name collision), there's nothing extra to delete here — `ExitWorktree` already correctly removes the original `worktree-<name>` branch on its own, and forcing a delete of some other name at this point is exactly the mistake to avoid.
  - If kept, the work stays on the worktree's branch, not the original tree's current branch — running `/git-pr` or `/git-ship` from here won't see it; re-enter the worktree (`EnterWorktree` with `path: <worktree path from the earlier confirmation message>`) to continue from there, or work from the branch directly with plain git commands.
