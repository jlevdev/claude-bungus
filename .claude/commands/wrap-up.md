---
allowed-tools: Bash(git fetch:*), Bash(git branch:*), Bash(git worktree:*), Bash(git remote:*), Bash(git log:*), Bash(git checkout:*), Bash(git stash:*), Bash(git pull:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh issue view:*), Bash(gh project item-list:*), Bash(gh project item-edit:*), Bash(jq:*), Read, Edit, Write, Glob
description: Delete local branches and worktrees whose remote branch has been deleted, and close out any tickets that branch shipped
---

## Context
- Branches and their upstream tracking state: !`git branch -vv`
- Worktrees: !`git worktree list`
- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}'`

## Steps
1. Run `git fetch --prune` to update remote-tracking branches.
2. From the `git branch -vv` output above (re-run it after the prune), identify every local branch marked `: gone]`.
3. For each gone branch, **before deleting anything**, check whether it shipped any tickets:
   a. **Resolve whether this branch actually merged** — a gone remote alone doesn't distinguish a merge from an abandoned branch: `gh pr list --state merged --head <branch> --json number,title,url,mergedAt`. No merged PR found → do not touch any ticket or the changelog for this branch; fold it into the confirm-before-delete list (see Safety) rather than assuming it's safe to clean up. Found → continue to 3b.
   b. **Get the issues that PR closed** — `gh pr view <number> --json closingIssuesReferences --jq '.closingIssuesReferences[].number'` gives the ticket issue numbers GitHub itself resolved from the PR's `Closes: #N` lines (this is more reliable than grepping commit text — it's GitHub's own resolution of the closing keywords, and those issues are already closed as a side effect of the merge). No numbers → nothing to close out for this branch, skip to step 4.
   c. For each issue number found: confirm it's actually closed (`gh issue view <N> --json state`) — if still open despite appearing in `closingIssuesReferences`, note that discrepancy in the final report rather than guessing why, and don't touch its Ticket Status.
4. Before writing any ticket/changelog changes (step 5), make sure the working tree can actually update `CHANGELOG.md` cleanly — **this check applies whether or not a branch switch happens below, not only when one does**: `git status --short` first, and stop to ask if anything is already staged or `CHANGELOG.md` itself already has uncommitted changes, rather than risking step 6's commit sweeping in unrelated work. Then, if the current branch isn't the default branch, stash any remaining uncommitted work — `git stash push --include-untracked` (plain `git stash` skips untracked files, which can block the upcoming checkout if paths conflict), noting plainly that a stash now exists so every later exit path (below, and step 7) accounts for it — check out the default branch, and pull. **If checkout or pull fails here**, pop the stash immediately (back onto the branch you were on, which the failed checkout means you're still on) before reporting the failure — don't leave it dangling just because step 7 was never reached.
5. For every issue confirmed closed in step 3: set its Ticket Status to `Done` on the project board. Resolve the field/option/project ids from `.claude/github-project-config.json` (written by `/bg:init` — don't re-derive or hardcode them) and the item id from `gh project item-list <project-number> --owner <owner> --format json`, matching on the issue's URL/number:
   ```bash
   gh project item-edit --id <item-id> \
     --project-id "$(jq -r '.project.id' .claude/github-project-config.json)" \
     --field-id "$(jq -r '.ticketStatusField.id' .claude/github-project-config.json)" \
     --single-select-option-id "$(jq -r '.ticketStatusField.options.Done' .claude/github-project-config.json)"
   ```
   Then append one entry to `CHANGELOG.md` — right after the marker comment near the top, **replacing** the `*No shipped changes yet.*` placeholder line if it's still there rather than leaving it in place above the new entries — with the date, issue number, a one-line summary drawn from the issue title, and the merged PR's URL from step 3a. Batch every ticket closed this run into it.
6. If step 5 changed anything: `git add CHANGELOG.md`, commit with a conventional message listing what shipped, using bracket-tagged ticket references so `pr-review`'s commit-message parser (which looks for `[#N]`, not a bare `#N`) picks them up — e.g. `chore(tickets): close out [#12] [#7] (merged)` — then `git push`. If the push fails (protected branch, diverged history, etc.), leave the commit local rather than retrying blindly — the changelog state is correct locally even if unpushed — but **still run step 7 before reporting the failure**; "leave the commit local" means don't retry the push, not skip restoring the workspace.
7. If step 4 switched off the original branch, decide whether to restore it: **if the original branch is itself one of the gone branches slated for deletion in steps 8-9, stay on the default branch instead** — restoring it here would leave it checked out and make step 9's `git branch -D` on it fail, and there's nothing meaningful to return to anyway once its remote is gone. In that case, if step 4 stashed anything, still pop it — just onto the default branch you're staying on, not the branch about to be deleted — and say so in the report. Otherwise (the original branch survives), return to it now (`git checkout -`, then `git stash pop` if something was stashed) — unconditionally, whether step 6 succeeded or failed. Either way, say plainly in the final report which branch the session ends on and whether a stash was popped, so neither is ever a silent surprise.
8. For each gone branch not held back by step 3a's merge check: check whether it's checked out in a worktree (see the list above). If so, remove the worktree first: `git worktree remove <path>`.
9. Delete the branch: `git branch -D <name>`.
10. Report: branches removed, tickets set to `Done` (with their new changelog lines), any branches held back pending confirmation, and whether the bookkeeping commit pushed cleanly. If nothing was gone, say so explicitly — that's a good result, not a no-op to apologize for.

## Safety
- Never delete the current branch or the repository's default branch (`main`/`master`), even if it somehow shows as gone.
- If more than 5 branches would be deleted at once, list them and confirm with the user before deleting any. Also list, separately, any branch step 3a couldn't confirm as merged — deleting those needs the same explicit confirmation regardless of the 5-branch threshold, since "gone but unconfirmed" is exactly the case that risks silently losing an abandoned-but-unmerged branch's only copy.
- This only touches branches whose *remote* is already gone — it never deletes a remote branch or force-pushes anything itself.
- Ticket-closing (steps 3-6) only ever reads issue/PR state via `gh` and writes the project item's Ticket Status field plus `CHANGELOG.md` — it never edits issue content.
