---
name: implement-and-tutor
description: This skill should be used when the user wants to plan and be coached through a ticket they intend to implement themselves, rather than have the agent build it — e.g. "let's plan #12 before I code it", "critique my approach for #7", "I want to build #4 myself, walk me through it", "help me learn this stack while I work on #9" — or says "/implement-and-tutor". Human-driven counterpart to `implement`: the agent never writes the ticket's code, only critiques the human's plan and prepares stack-specific guidance.
argument-hint: <#N> [more issue numbers...]
allowed-tools: [Read, Write, Edit, WebFetch, WebSearch, Glob, Grep, AskUserQuestion, Bash(gh project item-edit:*), Bash(gh project item-list:*), mcp__github__issue_read, mcp__github__issue_write, mcp__github__search_issues, mcp__github__projects_get, mcp__github__projects_list]
version: 1.0.0
---

# Implement & Tutor

Plan and critique a ticket the *human* is about to implement — the agent never writes this ticket's code. Compare with `implement`, which is agent-driven end to end. Use this one when the point is for the user to write and learn the code themselves, with the agent as a planning critic and a source of stack-specific footing rather than a builder. See `CLAUDE.md`'s "Ticket System" section for the field schema.

## How this differs from `implement`
Same ticket system, same Ticket Status field, opposite division of labor. `implement` reads acceptance criteria and writes tests and code against them. This skill reads acceptance criteria, asks the human what *they* plan to do about them, pressure-tests that plan, and stops — no tests, no implementation code, no reviewer-gate subagents (there's no diff yet to review). The human goes and writes the code after this skill finishes; `check-in` and `git-ship`'s reviewer gate are what look at what they actually built.

## Pre-flight

1. Read `CLAUDE.md` — tech stack, conventions, constraints.
2. Read `PRD.md` — full project context and requirements.
3. Locate each referenced ticket via `issue_read` (by issue number). If a number doesn't resolve to an issue, say so and stop rather than guessing which one was meant.
4. Check for blocking open questions: `search_issues` for open issues labeled `type:question` whose body's `## Blocks` section references this ticket's number. If any exist, surface them to the user and stop — do not begin planning until they're answered or explicitly waived.
5. Set each target ticket's Ticket Status to `In Progress` — same mechanism `implement` uses and for the same reason (a deterministic, auditable single-field flip): `gh project item-edit`, with the project id, Ticket Status field id, and status option id (from `.claude/github-project-config.json`) typed as literal values in the command itself, never a shell variable:
   ```bash
   gh project item-edit --id <item-id> --project-id <project id> --field-id <ticket status field id> --single-select-option-id <status option id>
   ```
   Resolve `<item-id>` via `gh project item-list <number> --owner <owner> --format json` if not already known.
6. Scan existing source code relevant to this ticket to understand current patterns, naming conventions, and architecture — same as `implement`'s pre-flight, since the critique in Step 2 below needs to compare the human's plan against what's actually there, not just what CLAUDE.md says in the abstract.

## Step 1 — Ask for the plan

Ask the user directly, in plain conversation — not via `AskUserQuestion`, since this needs a free-form explanation, not a bounded choice — what their implementation approach is for this ticket: what they intend to change, in what order, and any design decisions they're already leaning toward. Wait for their answer before critiquing anything.

## Step 2 — Critique the plan

Check the plan against:
- **Acceptance criteria coverage** — does every criterion on the ticket have something in the plan that addresses it? Call out any that don't.
- **Dependencies** — if the ticket's `## Dependencies` section lists other tickets, confirm those are actually `Done` (or at least `Review`) before this plan can proceed as described.
- **Fit with existing patterns** — does the plan match the architecture and conventions already in the codebase (from Pre-flight step 6) and documented in `CLAUDE.md`, or does it introduce a genuinely different approach? A different approach isn't automatically wrong, but surface it explicitly rather than letting it pass silently.
- **Risk and edge cases** — the failure modes and edge cases the ticket's acceptance criteria imply that the plan doesn't mention.

If something in the plan can't be resolved by discussion (a genuine ambiguity in the ticket, a missing dependency, a conflicting spec) — same rule as `implement`: open a GitHub issue labeled `type:question` using `templates/question.md`'s structure via `issue_write`, note which ticket it blocks, and stop rather than guessing an answer that could require significant rework later.

## Step 3 — Stack conventions reference

Identify the language/framework this ticket is actually built in (from `CLAUDE.md`'s Tech Stack table, or the ticket itself if it introduces something not yet listed there).

1. Check whether `references/<stack>.md` already exists for it (e.g. `references/dotnet-csharp.md`, `references/react-typescript.md`). Sanitize `<stack>` the same way `research` sanitizes a research-log topic — lowercase, non-`[a-z0-9-]` characters replaced with `-`, collapsed and trimmed, resolved under `references/` and never allowed to escape that directory via a raw value containing `../`.
2. **If it exists**, read it and pull out the parts relevant to what this ticket's plan touches — surface those in Step 4 alongside the critique.
3. **If it doesn't exist**, build one now using `research`'s own protocol (`.claude/skills/research/SKILL.md`) — same threat-model awareness (`references/threat-model.md`) and source requirements (minimum 3 independent sources) apply here too; this isn't exempt just because the output isn't a dated log. Scope the research to idiomatic patterns and common anti-patterns for this specific language/framework, not a tech-selection comparison. Save the result to `references/<stack>.md` rather than a dated `research/YYYY-MM-DD-topic.md` file — this is a living reference meant to be read by `check-in`'s `convention-reviewer` agent on every future ticket in this stack, and updated in place as it's refined, not re-created per ticket.

## Step 4 — Give pointers

Summarize for the user, concretely:
- What the critique in Step 2 surfaced (gaps, risks, fit concerns) — with specific pointers on what to address before or while writing the code.
- The relevant conventions/anti-patterns from `references/<stack>.md` (whether just read or just built) that bear on this specific ticket.
- A reminder of what's next: they write the code themselves; `check-in` is available any time before committing for a lightweight, idiom-focused pass against this same reference file; `git-ship`'s reviewer gate (`ticket-reviewer`, `silent-failure-hunter`, `test-coverage-reviewer`) is the mandatory check before Ticket Status can move to `Review`, since this skill's own flow never produces a diff for those to review.

Ticket Status stays `In Progress` when this skill finishes — it moves to `Review` later, at `git-ship` (see `CLAUDE.md`'s Sprint Flow).
