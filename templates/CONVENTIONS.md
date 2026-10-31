# Conventions

This repository's additions to the gaffer plugin's default conventions. Each section sits under a heading the plugin's `defaults/CONVENTIONS.md` documents and is read together with the plugin's section of the same name; this file wins where the two conflict. A section whose first line is exactly `Replaces the default.` is read instead of the plugin's section. Delete any section this repository has nothing to add under, and add a section under any heading of your own that a command should read.

## Build, test and format

- **Build-and-test command** — `<the one command that builds and runs the whole suite>`, run from the repository root. Required: `/build` and `/verify` stop without it.
- **Formatter** — `<the command CI checks, or delete this line to run with none>`.

## Test-driven development

<Where this repository states its TDD rule, if anywhere beyond the default, and anything particular about the configuration/tooling carve-out.>

## Testing

<Test projects, naming scheme, structure, the testing guide to read first, snapshot conventions, what not to test, and any hook that enforces the skipped-test ban.>

## Acceptance criteria

<Any drafting convention beyond the default, and the traceability check to run before raising a pull request, if there is one.>

## Code quality

<Standards, cross-platform or runtime constraints, build-time guarantees.>

## Dependencies

<The dependency-controlled library, if any, and its rule.>

## Public API and breaking changes

<The protected public surface, if any, and the versioning stance.>

## Commit messages

<Anything beyond `Refs #<N>: <imperative>` on a `feature/<N>-<slug>` branch.>

## Documentation

<What each kind of change owes: user docs for an option, API docs for a public member, release docs for a pipeline change.>

## Change-intent records

<"This project keeps them", the convention whose decision table `/build` runs, and where the records live — or delete the section to keep none.>

## Scratch files

<Only if scratch files live somewhere other than `.claude/scratch/`.>

## Pull requests

<The check that runs on the issue link, if any.>

## Issue sources

<The backlog a `backlog <number>` argument refers to, how to read a row, and how Related links it.>

## Issue concerns

<The requirements decisions this repository's issues must settle beyond the generic categories.>

## Issue review checks

<The checks `/reviewissue` considers beyond its generic categories.>

## Audit

<Scope, the evidence table, the rules each lens audits, what each lens should know about this tree, and the issue label.>

## Diagnose

<Fast, deterministic ways to reproduce a bug here, and the gotchas that waste an attempt — or a link to the document that lists them.>

## Hooks, scripts and plugins

<The hooks, scripts and plugins this repository wires in beyond the plugin's own: what each does, and what a command must weigh.>
