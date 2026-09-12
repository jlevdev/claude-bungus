---
allowed-tools: Read, Edit, Bash(git diff:*), Bash(git status:*), Glob, Grep
description: Add comments and docstrings to existing code without changing any logic
argument-hint: [file or path (optional — defaults to the current uncommitted diff)]
---

# /doc-code

Add documentation to code that already works — comments and docstrings only. This command never changes what the code does.

## Context
- Git status: !`git status`
- Staged and unstaged changes: !`git diff HEAD`

## Steps

1. **Determine targets.** If a file or path was given as an argument, use that. Otherwise, use every file in the diff shown above (`git diff --name-only HEAD` if that list needs regenerating).
2. **Read each target file in full** before editing — comments and docstrings need to be accurate to the whole function/class, not just the lines that changed.
3. **Add:**
   - Docstrings/doc-comments for functions, classes, and modules that don't have one — in whatever format the language/project already uses (JSDoc, Python docstrings, XML doc comments, Go doc comments, etc.). If the file has existing docstrings, match their format and level of detail exactly.
   - Inline comments only where the code's intent genuinely isn't obvious from reading it — not a comment restating what the next line already says.
4. **Never touch:** variable/function names, logic, control flow, formatting or whitespace of any executable line, imports, or anything else that isn't a comment or docstring. If a docstring you're about to write would require rewording the code to make sense, that's a sign the code needs a human decision, not a silent fix — write the docstring to accurately describe what the code *actually does*, and flag the mismatch in your summary instead of changing the code to match the doc.
5. **If an existing docstring is already wrong** (describes behavior the code doesn't have), flag it explicitly in your summary rather than silently correcting it — that's a real bug-adjacent finding worth the developer's attention, not something to paper over.
6. **After editing, confirm the guarantee this command exists for:** show a summary of exactly what was added per file, and confirm (via `git diff`) that no non-comment line changed. If anything besides a comment/docstring changed, that's a mistake — undo it before reporting done.

## Note
This is a command, not a skill — it only runs when explicitly invoked with `/doc-code`, precisely because "silently adds comments" isn't something that should ever auto-trigger from a casual question about the code.
