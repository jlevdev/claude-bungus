<!--
Issue-body template for a remediation ticket (bug/tech-debt/performance/security). This is pasted into
`issue_write`'s (or `gh issue create --body`'s) body — it is not saved as a standalone file. The issue itself
carries: number (the ticket ID, referenced as #N), title, and the following labels/metadata set alongside
creation:
  - type:bug | type:tech-debt | type:performance | type:security
  - priority:critical | priority:high | priority:medium | priority:low
  - effort:s | effort:m | effort:l | effort:xl
  - Milestone (native GitHub milestone, e.g. M1) if one applies
  - Added to the repo's GitHub Project with Ticket Status = Todo
-->

## Description

[What is broken, or what debt needs addressing? 2-3 sentences.]

## Steps to Reproduce *(bugs only)*

1.
2.
3.

## Expected Behavior

[What should happen]

## Actual Behavior

[What is currently happening]

## Root Cause *(if known)*

[Technical explanation — helps the implementer go directly to the right place]

## Acceptance Criteria

- [ ] Issue is resolved
- [ ] Regression test added to prevent recurrence
- [ ] No new test failures introduced

## Dependencies

- **Depends on:** [#N, #M — or "none"]
- **Blocks:** [#N, #M — or "none"]

## Test Coverage Required

[What regression test(s) must be added? Be specific so `/review-tests` can validate coverage.]
