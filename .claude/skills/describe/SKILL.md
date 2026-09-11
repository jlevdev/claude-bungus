---
name: describe
description: This skill should be used when the user wants a plain-language summary of one or more tickets — e.g. "describe #12", "explain what #7 is about", "summarize #1 and #4" — or says "/describe".
argument-hint: <#N> [more issue numbers...]
allowed-tools: [mcp__github__issue_read, mcp__github__search_issues, mcp__github__projects_get]
effort: low
version: 2.0.0
---

# Describe

Give the user a plain-language summary of one or more tickets. Tickets are GitHub Issues on this repo's GitHub Project — see `CLAUDE.md`'s "Ticket System" section for the field schema.

## Steps

1. Parse the issue numbers from the request (e.g., `#12`, `#7`).
2. For each number, fetch the issue via `issue_read` and its Ticket Status via `projects_get`.
3. For each ticket found, output:
   - **[#N] Title** *(Ticket Status)*
   - What it does in 2-3 sentences — plain language, no jargon
   - Acceptance criteria as a bulleted list
   - Dependencies (if any) — from the issue body's `## Dependencies` section
   - Effort/priority (from labels) and milestone (if set)
   - ⚠️ **Blocked by:** list any open `type:question` issues whose body's `## Blocks` section includes this ticket's number
4. If a number is not found as an issue, say so explicitly.

Keep the output scannable. No filler text.
