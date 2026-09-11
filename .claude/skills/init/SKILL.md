---
name: init
description: This skill should be used when the user wants to scaffold a fresh project's file structure from the claude-bungus template — e.g. "set up this project", "scaffold the ticket workflow here", "init this repo from the template" — or says "/init" or "/bg:init". Distinct from Claude Code's built-in codebase-documentation /init: this one lays down the PRD workflow files and the GitHub Projects ticket board, not a CLAUDE.md audit of existing code.
allowed-tools: [Read, Write, Bash, Glob, AskUserQuestion]
version: 2.2.0
---

# Init

Scaffold the ticket-based PRD workflow into the current project: `project blurb.md`, `templates/`, a GitHub Project board for tickets, `.mcp.json`, `DECISIONS.md`, `CHANGELOG.md`, and a starter `CLAUDE.md`. Run this once, before `/bg:start-project`, in a project that installed the `bg` plugin but doesn't yet have this scaffolding on disk.

This is a fresh-project setup step, not a codebase audit — don't confuse it with Claude Code's built-in `/init` (which writes a `CLAUDE.md` by reading existing code). If both are ambiguous from context, ask which the user means.

Tickets and blocking questions live as GitHub Issues, not local files — see `CLAUDE.md`'s "Ticket System" section (copied in step 3 below) for the full field schema. This step provisions the board those issues will live on.

## Steps

1. **Resolve the asset root, once, and reuse it for every copy step below.** The bundled assets live at `${CLAUDE_PLUGIN_ROOT}/templates/`. If `${CLAUDE_PLUGIN_ROOT}` isn't set (e.g. this skill is somehow running standalone rather than as part of the installed plugin), fall back to the current working directory itself (not its `templates/` subdirectory) — so `$ASSET_ROOT/templates/` still resolves to the project's own `./templates/`, matching the plugin-root case — but note this fallback to the user, since it means nothing was actually distributed. Call whichever path wins `ASSET_ROOT` for the rest of this skill's run. Every template file copied in step 3 — `templates/` itself, `DECISIONS.md`, `CHANGELOG.md`, and `CLAUDE.md` — must be sourced from `$ASSET_ROOT`, never from the project's own `./templates/` (which, if step 3 skipped recreating it because the user chose to keep an existing one, could be partial or stale — copying `DECISIONS.md`/`CHANGELOG.md` from it instead of from `$ASSET_ROOT` risks seeding the project root with an outdated or user-modified template instead of the plugin's canonical one).

2. **Check for conflicts.** Glob the current project root for `project blurb.md`, `templates/`, `CLAUDE.md`, `DECISIONS.md`, `CHANGELOG.md`, `.mcp.json`. If any already exist with real content (not just an empty dir or placeholder), list them and ask via `AskUserQuestion` whether to skip each one or overwrite it. Never silently clobber existing work — an empty/placeholder file (e.g. a zero-byte `project blurb.md`, or a `CLAUDE.md` that's still the untouched `[Project Name]` template) is safe to overwrite without asking. For `.mcp.json` specifically, don't `Read` it to check — the file isn't in this repo's protected-read patterns, so a plain read puts its full contents (auth headers included, even though they should only ever be `${VAR}` references per convention — no reason to rely on that convention when a narrower check costs nothing) into context. Use a redacted existence check instead, e.g. `jq -e '.mcpServers.github // empty' .mcp.json >/dev/null 2>&1` via Bash, which only tells you true/false. If it already declares a `github` server, treat GitHub MCP as already wired up, skip step 4 entirely, and skip the `.mcp.json` write in step 5 (merge/skip logic below still applies to everything else in the file).

3. **Create the local scaffold**, skipping anything the user chose to keep. Every copy sources from `$ASSET_ROOT` (step 1) regardless of what may or may not already exist at the project-local destination:
   - Copy `$ASSET_ROOT/templates/` → `./templates/` (all template files, including the issue-body templates `ticket-feature.md`, `ticket-remediation.md`, `question.md`).
   - Create a blank `project blurb.md` at the project root if one doesn't already exist.
   - Copy `$ASSET_ROOT/templates/DECISIONS.md` → `./DECISIONS.md` and `$ASSET_ROOT/templates/CHANGELOG.md` → `./CHANGELOG.md` (both unmodified — they're tool-maintained from here on, same as `/bg:start-project` step 3d-iii would otherwise do).
   - Copy `$ASSET_ROOT/templates/CLAUDE.md` → `./CLAUDE.md`. This is the distributed starter — it already documents the ticket workflow, reviewer subagents, and research standards with the `bg:` invocation prefix; only its top placeholder sections (`[Project Name]`, Tech Stack, etc.) still need filling in, which is `/bg:start-project`'s job, not this skill's.
   - Ensure `.gitignore` contains `research/*` and `.claude/pr-watch-state/` — append whichever lines are missing, create the file if it doesn't exist.

4. **Provision the GitHub Project board.** If `.claude/github-project-config.json` already exists, treat the board as already provisioned and skip straight to step 5. Otherwise, this requires `gh` to be authenticated (`gh auth status`) — if it isn't, tell the user to run `gh auth login` first and stop here.
   - Ask via `AskUserQuestion` who owns the board: the authenticated user, or an organization (if working in one) — `gh project create --owner <owner> --title "<repo/project name> Tickets" --format json`. Capture the returned project `number`/`id`/URL.
   - Add a custom single-select field for ticket status: `gh project field-create <project-number> --owner <owner> --name "Ticket Status" --data-type SINGLE_SELECT --single-select-options "Todo,In Progress,On Hold,Review,Done" --format json`. **Deliberately a new field, not GitHub's built-in default "Status" field** — the GraphQL API that backs `gh project field-create` can set options when *creating* a single-select field, but there is no supported way to edit the option set of an already-existing single-select field (including the built-in one), so scripting this against the default field isn't possible. The built-in Status field can be hidden from the board view later if its presence alongside Ticket Status is confusing — mention this to the user, don't do it automatically.
   - **Write `.claude/github-project-config.json`** from what the two commands above returned — this is the single source of truth every other command/skill/hook reads instead of re-deriving field/option ids:
     ```json
     {
       "project": { "number": <number>, "owner": "<owner>", "id": "<project id>" },
       "ticketStatusField": {
         "id": "<field id>",
         "options": {
           "Todo": "<option id>", "In Progress": "<option id>", "On Hold": "<option id>",
           "Review": "<option id>", "Done": "<option id>"
         }
       }
     }
     ```
     This file is checked into git (it's deterministic config, not a secret) — `require-tests-before-review.sh` reads it to recognize a move into `Review` and gate it on tests; `/bg:implement`, `/bg:start-project`, and `/bg:wrap-up` read it to resolve status names to ids without re-querying the API every time.
   - Create matching labels on the repo (`gh label create`) for anything not modeled as a field: `type:feature`, `type:bug`, `type:tech-debt`, `type:performance`, `type:security`, `priority:critical`, `priority:high`, `priority:medium`, `priority:low`, `effort:s`, `effort:m`, `effort:l`, `effort:xl`, `type:question`. Pick a distinct, low-saturation color per label group (type/priority/effort/question) rather than leaving everything GitHub's random default — skip any label that already exists.
   - Report the project number/URL and remind the user it's now the board `/bg:start-project` and `/bg:implement` will read/write.

5. **Wire up the GitHub MCP server.** Skip this step entirely if step 2's redacted check already found `mcpServers.github` — nothing to do. Otherwise:
   - The `github` entry to add is:
     ```json
     "github": {
       "type": "http",
       "url": "https://api.githubcopilot.com/mcp/",
       "headers": {
         "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}",
         "X-MCP-Toolsets": "issues,projects"
       }
     }
     ```
   - **If `.mcp.json` doesn't exist yet, or exists but is empty** (the same zero-byte case step 2 already treats as safe to overwrite — reuse that check here rather than branching on path existence alone, since an empty file isn't valid JSON to merge into), write it fresh with just that entry under `mcpServers`.
   - **If `.mcp.json` already exists with real content** (it has other servers, or the user chose "keep" in step 2 for a file that turned out not to have `github` in it yet), merge via `jq` — never via the `Read` tool or an unredirected Bash read, both of which would put the whole file's contents, auth headers included, into context for no benefit. Something like:
     ```bash
     jq '.mcpServers.github = {"type":"http","url":"https://api.githubcopilot.com/mcp/","headers":{"Authorization":"Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}","X-MCP-Toolsets":"issues,projects"}}' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
     ```
     writing to a temp file and moving it into place rather than an in-place edit that could corrupt the file on a mid-write failure. This adds/replaces only `mcpServers.github` and leaves everything else in the file untouched — never regenerate the file from scratch when it already exists; that's exactly what would silently delete an existing Context7 (or any other) entry. If step 2 recorded an explicit "skip" for `.mcp.json` as a whole, honor that and don't write to it at all — tell the user GitHub MCP still needs wiring up by hand in that case.

   `.mcp.json` is project-scoped and gets checked into git so the whole team gets the same servers automatically — never put a literal token in it, only the `${VAR}` reference. Document `GITHUB_PERSONAL_ACCESS_TOKEN` in `CLAUDE.md` under a new `## MCP Servers` section: a classic PAT with `repo` and `project` scopes is the reliable path for both reading/writing issues and reading/writing the Project board; note that fine-grained PATs have historically had narrower or inconsistent Projects v2 support, so point the user at GitHub's current token-creation UI to confirm what's available rather than asserting one exact permission name here. Offer Context7 MCP too, same as before (optional, for live doc lookups) — see `/bg:start-project` step 3f for its config shape, unchanged by this migration.

6. **Report what was created and skipped**, then point the user at the next step: fill in `project blurb.md` with their idea, set `GITHUB_PERSONAL_ACCESS_TOKEN`, then run `/bg:start-project`.

## Notes

- This skill only lays down structure — it never runs `git init` or commits anything. `/bg:start-project` still owns that (its step 3e), so a user can review the scaffold before it's committed.
- If the project has no `.claude-plugin` install context at all (i.e. someone copied these files by hand instead of installing the `bg` plugin), that's fine — the scaffold still works, just without the "pull future updates via `claude plugin update`" benefit. Mention this once if it's the case, don't belabor it.
- If `gh` isn't the git platform CLI in play (e.g. GitLab per `CLAUDE.md`'s Tech Stack table), step 4/5 don't apply — this workflow is GitHub-specific; note that to the user and skip straight to step 6, since the rest of the scaffold (templates, PRD, decisions/changelog) is still useful without the board.
