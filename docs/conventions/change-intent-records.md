# Change Intent Records (CIRs)

**Scope**: Documenting non-obvious development decisions
**Location**: `docs/change-intent-records/`
**Audience**: Future maintainers, AI agents, code reviewers

---

## What are Change Intent Records?

Change Intent Records capture the **why** behind non-obvious decisions made during development: the reasoning, the alternatives considered, and the constraints that led to a particular implementation choice.

They are where reasoning that argues a decision goes, because a comment points out a gotcha rather than arguing one. The comment links the record; `CONVENTIONS.md` → *Code quality* is the comment rule, and the decision table below decides whether a record is warranted.

An issue thread cited for its reasoning is standing in for a record that was never written. Write the record and link that instead.

**Decision table** — does this change need a CIR?

| Question | → CIR | → No CIR |
| --- | --- | --- |
| Choosing between multiple viable approaches a future maintainer would reasonably question? | ✅ | |
| Working around a limitation or constraint the code or prompt itself won't make obvious? | ✅ | |
| Architectural decision that constrains future work (an interface in `docs/interfaces.md`, the verdict schema, how the commands divide the work)? | ✅ | |
| Trade-off made (robustness vs. cost, locality vs. DRY, simplicity vs. flexibility) where the rejected option is plausible? | ✅ | |
| Following an established pattern already documented elsewhere in the repo? | | ✅ |
| Obvious or standard implementation with no real alternative? | | ✅ |
| Temporary workaround you expect to remove? | | ✅ (a comment describing the current state, with the removal tracked in an open issue) |
| Reasoning already recorded in the issue's confirmed decisions, and the change constrains no interface a repository or the chain depends on? | | ✅ (link the issue from the commit message or the pull request body rather than restating it) |
| Change only to documentation written for the plugin's readers, such as `README.md` or `docs/getting-started.md`? | | ✅ (commands, `defaults/`, `templates/` and the chain scripts direct future work and are not covered by this row) |

Write a record when a `→ CIR` row applies **and** no `→ No CIR` row does. Most changes need none.

The confirmed-decisions row leaves out a change that constrains future work because an issue closes and is not read again, while the interface it shaped stays. Such a decision gets a short record linking the issue for its reasoning.

## CIR Template

Save CIRs in `docs/change-intent-records/` as `YYYY-MM-DD-kebab-title.md`.

```markdown
# [Descriptive Title]

**Intent:** What was the goal or objective?

**Behaviour:** The expected outcome in a sentence or two — or a one-line pointer where the issue, a command or a doc already specifies it.

**Constraints:** What boundaries or guardrails applied?

**Decisions:** What alternatives were considered and rejected, and why?

**Date:** YYYY-MM-DD
```

**Target about 150 words.** A record states its intent in a sentence, and then keeps only what is written nowhere else: each rejected alternative with the reason it was rejected, and any constraint the code will not make obvious. Everything else is linked rather than restated — behaviour to the issue, review notes to the pull request, a documented rule to the command or doc that carries it. Write one-line bullets, not paragraphs.

Each piece of reasoning is written once. A rejected alternative belongs in the record, so where a record exists the pull request body points to it instead of repeating its reasoning.

When a record overturns part of an earlier one, add `**Supersedes:** <link> — <which decision>` so the older record is read in light of the newer.

**A worked sample at the target length.** This is condensed from the decision to read a stage's verdict by position:

```markdown
# The chain reads each stage's verdict by position

**Intent:** Stop the chain mistaking what a stage's report quotes for what the stage decided, in both directions.

**Behaviour:** See `docs/verdict-schema.md` → *How a verdict is read*.

**Constraints:** A false stop costs the rest of one run done by hand; a false success opens a pull request off unverified work.

**Decisions:**

- Rejected: a channel outside the prose, such as a file each stage writes. More robust, but a much larger change that still needs a fail-safe for a stage that records nothing.
- Rejected: a stricter prose scan that counts only an undecorated verdict at the start of a line. Cheaper, but it still cannot tell a stage's own verdict from one the report quotes; a quotation cannot fake being last.

**Date:** 2026-10-09
```

## References

- [Change Intent Records (Bryan Liles)](https://blog.bryanl.dev/posts/change-intent-records/)
- Architecture Decision Records (ADRs) - similar concept
