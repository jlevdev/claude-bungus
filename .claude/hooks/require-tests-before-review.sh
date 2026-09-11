#!/bin/bash
# Runs the project's test suite before a ticket is allowed to move to Ticket
# Status "Review" on the GitHub Project board. Registered as a PreToolUse
# hook on Bash, unconditionally -- scoping is done internally below (checking
# the command for a `gh project item-edit` call that targets the Ticket
# Status field's Review option) rather than via the dispatcher's "if" field.
#
# This makes /implement's "confirm the full test suite still passes" step
# (see .claude/skills/implement/SKILL.md) enforced rather than just
# instructed. Ticket status lives on GitHub now (see CLAUDE.md's "Ticket
# System" section), not in a tickets/**/review/ file path, so this can't
# pattern-match a path the way it originally did -- it instead resolves the
# Review option's id from .claude/github-project-config.json (written by
# /bg:init when the board's Ticket Status field is created) and checks
# whether the command's --field-id/--single-select-option-id pair matches it.
#
# Best-effort: if no test command can be detected, or the project config
# file doesn't exist yet (expected for this template before it's scaffolded
# into a real project), it warns and lets the command through instead of
# blocking on nothing.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only act on `gh project item-edit` calls -- everything else is out of scope.
if ! echo "$COMMAND" | grep -qE 'gh project item-edit'; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

CONFIG_FILE=".claude/github-project-config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "require-tests-before-review: no $CONFIG_FILE found yet, allowing the command. Once /bg:init provisions the project board, this hook will recognize moves into Review and gate them on tests." >&2
  exit 0
fi

FIELD_ID=$(jq -r '.ticketStatusField.id // empty' "$CONFIG_FILE" 2>/dev/null)
REVIEW_OPTION_ID=$(jq -r '.ticketStatusField.options.Review // empty' "$CONFIG_FILE" 2>/dev/null)

if [[ -z "$FIELD_ID" || -z "$REVIEW_OPTION_ID" ]]; then
  echo "require-tests-before-review: $CONFIG_FILE is missing ticketStatusField.id or .options.Review, allowing the command rather than blocking on an unreadable config." >&2
  exit 0
fi

# This is a move into Review only if the command references both the Ticket
# Status field and its Review option -- either alone could belong to an edit
# of a different field or a different option (Todo/In Progress/On Hold/Done).
if ! echo "$COMMAND" | grep -qF -- "$FIELD_ID" || ! echo "$COMMAND" | grep -qF -- "$REVIEW_OPTION_ID"; then
  exit 0
fi

detect_test_command() {
  if [[ -f package.json ]]; then
    if grep -q '"test"' package.json && ! grep -q 'Error: no test specified' package.json; then
      if [[ -f pnpm-lock.yaml ]]; then echo "pnpm test"; return; fi
      if [[ -f yarn.lock ]]; then echo "yarn test"; return; fi
      if [[ -f bun.lockb ]]; then echo "bun test"; return; fi
      echo "npm test"
      return
    fi
  fi
  if [[ -f pyproject.toml || -f pytest.ini || -f setup.cfg ]]; then
    echo "pytest"
    return
  fi
  if [[ -f Cargo.toml ]]; then
    echo "cargo test"
    return
  fi
  if [[ -f go.mod ]]; then
    echo "go test ./..."
    return
  fi
  echo ""
}

TEST_CMD=$(detect_test_command)

if [[ -z "$TEST_CMD" ]]; then
  echo "require-tests-before-review: no test command detected yet, allowing the move. Once a stack is chosen (see CLAUDE.md), this hook will run it automatically before tickets can reach Review." >&2
  exit 0
fi

echo "require-tests-before-review: running '$TEST_CMD' before allowing this ticket into Review..." >&2

LOG_FILE=$(mktemp)
if ! (eval "$TEST_CMD") > "$LOG_FILE" 2>&1; then
  echo "Blocked: '$TEST_CMD' failed, so this ticket can't move to Review yet. Last 40 lines of output:" >&2
  tail -n 40 "$LOG_FILE" >&2
  rm -f "$LOG_FILE"
  exit 2
fi

rm -f "$LOG_FILE"
exit 0
