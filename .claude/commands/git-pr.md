---
allowed-tools: Bash(git log:*), Bash(git branch:*), Bash(git status:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(glab mr create:*), Bash(glab mr view:*)
description: Open a pull request on GitHub (or GitLab) for the current branch using the CLI
---

## Context
- Current branch: !`git branch --show-current`
- Recent commits on this branch: !`git log --oneline -15`
- Existing PR for this branch, if any (GitHub only — see Steps for GitLab): !`gh pr view --json url,state`

## Default platform: GitHub
This project uses GitHub. Use `gh` for all PR operations. If a specific project overrides this in its `CLAUDE.md` Tech Stack table to GitLab, use `glab mr create` instead.

## Create a PR
```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

## PR body template
```
## What
- <change 1>
- <change 2>

## Why
<motivation — reference ticket IDs>

## Test plan
- [ ] All existing tests pass
- [ ] <specific verification step>
- [ ] <another step>

## Tickets
Closes: #N, closes: #M
```
Using GitHub's native closing-keyword syntax means the referenced issue auto-closes when this PR merges — don't substitute a plain `#N` mention if the intent is actually "this PR finishes that ticket." **Repeat the keyword for every issue** — GitHub requires a complete keyword/reference pair per issue; `Closes: #N, #M` only closes `#N`, since the bare `#M` after it has no keyword of its own.

## Steps
1. If this project's `CLAUDE.md` specifies GitLab, the context above doesn't apply — it's a GitHub-only prefetch. Run `glab mr view` instead to check for an existing merge request before creating one. Otherwise, check the context above — if a PR already exists for this branch, show it to the user and ask whether they want to update it instead of creating a new one.
2. Look up the ticket issue(s) referenced in commit messages (`gh issue view <N>`) for context — tickets live on GitHub Issues regardless of which platform hosts the PR/MR itself, so this applies the same way whether Step 1 took the GitHub or GitLab branch.
3. Draft the title (under 70 chars) and body using the template above.
4. Confirm the draft with the user before creating.
5. Create the PR and return the URL.

## Notes
- Ensure `gh auth login` has been run before first use.
- For GitHub Enterprise: `gh` works the same way; run `gh auth login --hostname <your-host>`.
- For a project that uses GitLab instead: use `glab mr create --title "<title>" --description "<body>"`. Ensure `glab` is installed and `glab auth login` has been run.
