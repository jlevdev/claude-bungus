---
name: migrate-tickets
description: This skill should be used when the user wants to migrate an existing project's .md-file tickets and questions (tickets/features/*, tickets/remediation/*, questions/open|answered/*) onto this repo's GitHub Issues + Projects workflow — e.g. "migrate our tickets to GitHub", "convert the old ticket files", "move to the new ticket system" — or says "/migrate-tickets" or "/bg:migrate-tickets". One-time migration for a project that started on the old file-based system before it moved to GitHub; the ongoing workflow afterward is `/bg:implement`, `/bg:whats-next`, `/bg:describe`, `/bg:wrap-up` — this skill doesn't replace any of those, it just gets a project from the old state to the new one.
argument-hint: (no arguments — scans the whole tickets/ and questions/ trees)
allowed-tools: [Read, Write, Bash, Glob, Grep, AskUserQuestion, mcp__github__issue_read, mcp__github__issue_write, mcp__github__search_issues, mcp__github__list_issues]
version: 1.1.0
---

# Migrate Tickets

Move an existing project's file-based tickets and questions onto GitHub Issues + a GitHub Project board, matching the schema in `CLAUDE.md`'s "Ticket System"/"Questions" sections. Read that section first if you haven't already — this skill produces exactly what it describes, nothing bespoke.

This creates real external state (GitHub issues, project items, milestones) — treat every bulk-creation step as something to confirm before running, not after.

## Step 1 — Detect scope

Glob `tickets/{features,remediation}/{todo,in-progress,on-hold,review,done}/*.md` and `questions/{open,answered}/*.md`. If both are empty, say so and stop — nothing to migrate. Report counts per folder before continuing.

## Step 2 — Confirm the board exists

Check for `.claude/github-project-config.json`. If it's missing, this project hasn't been provisioned onto GitHub Projects yet — don't provision it here; tell the user to run `/bg:init`'s board-provisioning step first (it's steps 4-5 of `.claude/skills/init/SKILL.md`), then re-run this skill. Duplicating that logic here would give the config file two different places it could be created from, which is exactly the kind of drift `.claude/github-project-config.json` exists to prevent.

## Step 3 — Parse every source file

For each ticket file: read its YAML frontmatter (`id`, `title`, `priority`, `effort`, `milestone`, `created`, and for remediation tickets `type`) and body. Status comes from which status folder it's in (`todo`/`in-progress`/`on-hold`/`review`/`done`); type comes from `features/` vs `remediation/` plus, for remediation, the file's own `type:` field (`bug`/`tech-debt`/`performance`/`security`) — `features/` tickets are always `type:feature`.

For each question file: read its frontmatter (`id`, `status`, `raised-by`, `raised-date`, `blocks`) and body (`## Question`, `## Context`, `## Options Considered`, `## Answer`, `## Resolution Impact`). `questions/open/` → still-open; `questions/answered/` → answered.

## Step 4 — Dry-run summary, then confirm

Before creating anything, show: total tickets by type and target Ticket Status, total questions by open/answered, and flag anything that looks malformed (missing frontmatter fields, an unparseable status folder). Ask via `AskUserQuestion`: proceed with migration (recommended) or cancel. Don't skip this for a small batch — even 2-3 tickets is still real, externally-visible GitHub state once created.

## Step 5 — Idempotency marker

Every issue this skill creates gets `<!-- migrated-from: <old-id> -->` as the first line of its body (invisible in GitHub's rendered view, same convention as this repo's other issue-body templates using HTML comments for non-content notes). Before creating an issue for a given old id, `search_issues` for an existing open-or-closed issue whose body contains that exact marker — if found, skip creation and reuse its issue number for the mapping table in Step 7. This makes a re-run after a partial/interrupted migration safe: already-migrated items aren't recreated.

## Step 6 — Pass 1: create issues

Process tickets before questions (questions can reference ticket ids in `blocks`, and having tickets' numbers already assigned makes Step 7's remap strictly additive). Within tickets, order doesn't otherwise matter — process deterministically (e.g. features before remediation, ascending old id) so a report is easy to read and a re-run is easy to reason about.

**Per ticket** (skip per Step 5 if already migrated):
- Title = the ticket's `title` field.
- Body = the marker line, then the original body reformatted to match `templates/ticket-feature.md` / `templates/ticket-remediation.md`'s section structure (it should already be close — these were the same templates the old files were written from).
- Labels: `type:<feature|bug|tech-debt|performance|security>`, `priority:<critical|high|medium|low>`, `effort:<s|m|l|xl>` (lowercased from frontmatter).
- Milestone: if the frontmatter has one and it doesn't already exist on the repo, create it (`gh api repos/{owner}/{repo}/milestones -f title=<milestone>`) before attaching — verify the exact `gh api` shape against current docs when this is actually run rather than assuming the flags above are exact, the same way `/bg:init`'s provisioning commands were verified before being written down as fact.
- Add to the project board and set Ticket Status to whatever the source folder implies, using `gh project item-add`/`item-edit` with ids resolved from `.claude/github-project-config.json` — identical mechanics to `/bg:wrap-up`'s status-setting step; don't reinvent that pattern here. **If the source folder is `tickets/**/done/`**, also close the issue (`gh issue close <N>`) right after setting Ticket Status to `Done` — a Done ticket that's still open on GitHub is a contradiction the board alone doesn't catch.
- Record `<old-id> → <new #N>` in the shared mapping table (the same one Step 5 adds reused/already-migrated ids to — Step 7 needs the complete set, not just what this pass created).

**Per question** (skip per Step 5 if already migrated): create with the `type:question` label, the marker line, and body reformatted to `templates/question.md`'s structure — **explicitly**, populate the `## Blocks` section from the source file's parsed `blocks` frontmatter field (Step 3), the same way a ticket's `## Dependencies` gets populated from its own parsed frontmatter; don't leave this implicit in "reformatted to the template's structure," since it's the one piece of frontmatter that doesn't otherwise have an obvious body-section home. Not added to the project board — questions aren't board items (see `CLAUDE.md`'s "Questions" section). If it came from `questions/answered/`: create it open, then immediately close it with the original `## Answer`/`## Resolution Impact` content as the closing comment (GitHub has no create-already-closed call, so this is always two steps). If from `questions/open/`: leave it open. Record `<old-id> → <new #N>` in the same mapping table (created or reused, same as tickets).

## Step 7 — Pass 2: remap cross-references

Every issue in this run's mapping table — **whether created in Step 6 or found already-migrated and reused per Step 5** — may still reference old ids inside its `## Dependencies` (tickets) or `## Blocks` (questions) section: a freshly-created one because Step 6 copied body content verbatim before every id had a number, and a reused one because an earlier, interrupted run might have finished Pass 1 (creating it) without ever reaching Pass 2 (remapping it). Don't scope this pass to "issues just created this run" — run it over the complete mapping table every time, so a resumed migration finishes the remap on anything a prior partial run left half-done. For each one, re-read its body, replace every old-id token (`feat-N`, `rem-N`, `q-N`) found there with `#<mapped number>` from the table, and write the body back (`issue_write`/`gh issue edit --body`). If a token doesn't resolve (it referenced something outside this migration's scope — already done and archived elsewhere, or simply not found), leave it as literal text and flag it in the Step 8 report rather than guessing or silently dropping it.

## Step 8 — Report, then offer cleanup

Show a final table: old id → new `#N` → URL, for everything migrated or already-found-migrated, plus anything flagged in Step 7. Then ask via `AskUserQuestion`: delete the now-migrated local ticket/question files (recommended — git history keeps them, and GitHub is the source of truth from here on) or leave them in place. On confirm, delete only the specific files that were actually migrated or already found migrated this run (`git rm`) — never a blanket `rm -rf tickets questions`, since a flagged/failed item's source file should stay put for a retry. If every file in a status folder ends up empty, that's fine to leave as an empty directory; don't remove `tickets/`/`questions/` themselves unless the user separately asks (a partially-migrated project might still have files land there later).

## Step 9 — Wrap up

Remind the user the ongoing workflow is now `/bg:implement #N`, `/bg:whats-next`, `/bg:describe #N`, `/bg:wrap-up` — this skill doesn't run again as part of normal work, only if there's another batch of old files to bring over later.
