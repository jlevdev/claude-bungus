<!--
Issue-body template for a feature ticket. This is pasted into `issue_write`'s (or `gh issue create --body`'s)
body — it is not saved as a standalone file. The issue itself carries: number (the ticket ID, referenced as
#N), title, and the following labels/metadata set alongside creation:
  - type:feature
  - priority:critical | priority:high | priority:medium | priority:low
  - effort:s | effort:m | effort:l | effort:xl
  - Milestone (native GitHub milestone, e.g. M1) if one applies
  - Added to the repo's GitHub Project with Ticket Status = Todo
-->

## Description

[What does this feature do and why does it exist? 2-3 sentences. Focus on the user value, not the implementation.]

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Technical Notes

[Implementation hints, API contracts, architectural constraints, edge cases to handle. Leave blank if none yet.]

## Dependencies

- **Depends on:** [#N, #M, or an external system — or "none"]
- **Blocks:** [#N, #M — or "none"]

## Test Coverage Required

[Specific scenarios that must have test coverage. Be explicit — `/review-tests` uses this to scope chaos monkey mutations.]

## Design / Assets

[Link to mockups, Figma frames, or design notes. Leave blank if none.]
