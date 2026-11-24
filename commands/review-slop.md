---
description: Review the current branch diff against main for AI-generated code slop — unnecessary or stylistically inconsistent code that compiles and passes lint but degrades the codebase.
reference: https://www.josecasanova.com/prompts/ai-code-slop-reviewer
---

You will be reviewing a code diff against main to identify and remove "AI code slop" - unnecessary or stylistically inconsistent code that was likely added by AI code generation tools. Your goal is to produce a cleaned version of the diff with all such slop removed.

## Repository conventions

The comment rule this review holds comments to lives in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Read the default section first, then the repository's, which wins where they conflict and stands alone where its first line is `Replaces the default.`. The heading this command reads:

| Heading | Supplies |
|---|---|
| `Code quality` | the comment rule criterion 1 judges every added or changed comment against |

Where neither file states a comment rule, criterion 1 runs on its generic text alone.

## Review

"AI code slop" refers to code patterns that are characteristic of AI-generated code but inconsistent with human coding practices or the existing codebase style. Specifically, you should identify and remove:

1. **Excessive or unnatural comments**: Comments that over-explain obvious code, are overly verbose, or break the comment rule (`CONVENTIONS.md` → *Code quality*). Judge each comment the diff adds or changes against that rule, not against the file: a comment that breaks it is slop even where the rest of the file — including comments this same branch wrote — shares its style. Cut it as the rule says, or remove it. Leave comments the diff does not touch alone. Commented-out code counts too: delete it, git remembers.

2. **Unnecessary defensive programming**: Extra try/catch blocks, null checks, or validation that is abnormal for that area of the codebase, especially in code paths where inputs are already trusted or validated upstream.

3. **Type system workarounds**: Casts to `any` or other type assertions used to bypass type-checking issues rather than properly fixing the types.

4. **Stylistic inconsistencies**: Any code patterns, naming conventions, formatting choices, or structural approaches that differ from the established patterns in the file or codebase. Comments are judged by criterion 1, never by matching the file.

5. **Over-engineering**: Unnecessarily complex solutions where simpler code would suffice and match the codebase style.

To complete this task:

First, use a scratchpad to analyze the diff:

- Review each changed section in the diff
- Compare additions against the context of existing code
- Identify specific instances of AI slop with line references
- Note the patterns that appear to be AI-generated versus human-written

Then, provide the cleaned diff with all AI slop removed. The cleaned diff should:

- Maintain all legitimate functional changes
- Remove only the slop elements identified above
- Preserve the diff format (showing what was added/removed)
- Keep code that is functionally necessary and stylistically consistent

Your final output should be the complete cleaned diff. Present this inside <cleaned_diff> tags. If no slop was found, return the original diff unchanged and note that no changes were needed.
