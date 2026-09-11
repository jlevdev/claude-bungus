---
allowed-tools: Bash(git branch:*), Bash(git checkout:*), Bash(git status:*)
description: Create a new branch following project naming conventions
---

## Context
- Current branch: !`git branch --show-current`
- Existing local branches: !`git branch --list`

## Naming conventions
| Branch type | Pattern | Example |
|-------------|---------|---------|
| Feature | `feat/<issue-number>-<slug>` | `feat/12-user-auth` |
| Bug fix | `fix/<issue-number>-<slug>` | `fix/7-login-crash` |
| Chore / refactor | `chore/<slug>` | `chore/upgrade-dependencies` |
| Release | `release/<version>` | `release/1.2.0` |
| Hotfix | `hotfix/<issue-number>-<slug>` | `hotfix/19-null-pointer` |

**Slug rules:** lowercase, hyphens only, max ~30 characters after the prefix. The `feat/` vs `fix/` choice comes from the ticket issue's `type:` label (`type:feature` → `feat/`, anything else → `fix/`). A `type:question` issue is never branchable — questions aren't board items and aren't implemented; if asked to branch one, say so and stop rather than producing a nonsensical `fix/<N>-<slug>`.

## Steps
1. Identify the branch type from context (ticket issue number + its `type:` label, or user description).
2. Generate the slug from the ticket title or user description — keep it concise.
3. Check the existing branches listed above for a name collision.
4. Create and switch: `git checkout -b <branch-name>`
5. Confirm the branch was created and show the full name.

## Note
If no base branch is specified, branch off the current branch. If working on a feature that should branch from `main` or `develop`, confirm with the user first.
