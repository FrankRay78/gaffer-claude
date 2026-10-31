# Review criteria

This repository's additions to the gaffer plugin's default review criteria. Each section sits under a heading the plugin's `defaults/REVIEW.md` documents — the part of `/review-pr`'s method it extends — and is read together with the plugin's section of the same name; this file wins where the two conflict. A section whose first line is exactly `Replaces the default.` is read instead of the plugin's section. Delete any section this repository has nothing to add under. In CI the review reads the default branch's copy of this file, never the pull request's, so a change here takes effect on merge, and is itself a change that always needs the maintainer.

## Where it runs

<Which workflow runs `/review-pr` and `/review-followup`, on what trigger, as whom, and how it puts the default branch's copy of this file in place — or delete the section if both are run by hand.>

## Severity

<Which of this repository's rules count as mandatory, so a breach is Major.>

## What not to flag

<The checks CI already gates here, and what this repository has settled.>

## Risk tier

<The areas whose logic makes a change High, and any kind of change that is never Low.>

## Always a person

<The paths that need the maintainer whatever the tier.>

## Contracts

<What a user, a script or a consumer touches directly here, and the documents a change to one must update.>

## Context to load

<The documents to read for the layers a pull request touches.>

## Change map

<The areas to group changed files by.>

## Tests

<The test conventions a finding is judged against beyond the default.>
