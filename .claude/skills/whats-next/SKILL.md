---
name: whats-next
description: This skill should be used when the user asks for a status overview, what to work on next, or a sprint summary — e.g. "what's next", "what should I work on", "give me a status update", "what's blocked" — or says "/whats-next".
allowed-tools: [mcp__github__list_issues, mcp__github__search_issues, mcp__github__projects_get, mcp__github__projects_list]
effort: low
version: 2.0.0
---

# What's Next

Give the user a clear overview of current and upcoming work. Tickets are GitHub Issues on this repo's GitHub Project — see `CLAUDE.md`'s "Ticket System" section for the field schema.

## Steps

1. Query the project board (`projects_get`/`projects_list`) for open issues, grouped by Ticket Status: `In Progress`, `Todo`, `On Hold`. Read each item's `type:*`/`priority:*`/`effort:*` labels and Milestone via `list_issues`/`search_issues`.

2. Query open issues labeled `type:question` and note which ticket(s) each one's body `## Blocks` section references.

3. Present in this structure:

### Open Questions
Any open `type:question` issues. For each: **[#N]** the question, and which tickets it blocks. If there are none, omit this section.

### In Progress
Items with Ticket Status `In Progress`. Note how long they've been in-progress if the issue's `created` date suggests they've been here a while.

### Up Next — Features
Ticket Status `Todo` issues labeled `type:feature`, sorted by priority (critical → high → medium → low). If priorities are equal, use milestone order.

### Up Next — Remediation
Ticket Status `Todo` issues labeled `type:bug`/`type:tech-debt`/`type:performance`/`type:security`, same sort order. Critical bugs should always surface above medium-priority features.

### On Hold
Items with Ticket Status `On Hold`. For each, note what's blocking them — check the issue body's `## Dependencies` section.

For each ticket: `**[#N]** Title — one-line description (effort: S/M/L/XL)`

4. Flag dependency chains that constrain ordering (e.g., "#7 must come before #12") from each issue's `## Dependencies` section.
5. If an open question blocks a `Todo` ticket, mark that ticket with ⚠️ in the output.
6. If there are 3+ `Todo` items, suggest a sprint grouping — aim for a balanced set by effort (e.g., one L + two M, or four S items). Exclude tickets blocked by open questions from sprint suggestions.
7. Call out any critical or high-priority remediation items that should be pulled into the next sprint.
