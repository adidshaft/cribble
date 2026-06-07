---
name: Extension proposal
about: Propose a Cribble extension or plugin idea before implementation
title: "[Extension]: "
labels: ["extension", "proposal"]
assignees: ""
---

## Extension idea

Audience:

Workflow:

Why Cribble:

## First read-only version

Manifest kind:

What appears in Cribble:

What user reviews before anything changes:

## Data contract

Reads:

Writes:

Network:

Secrets:

Disable behavior:

## Native Mac surface

SwiftUI surface:

System controls or SF Symbols:

Settings, menu, command, sheet, or toolbar entry point:

## Later, not first PR

What would need executable code:

What would need project-wide reads:

What would need source-note writes:

## Safety checklist

- [ ] The first mergeable version can be declarative and read-only.
- [ ] Any write path uses an explicit preview/review/cancel flow.
- [ ] The proposal asks for the least note access that can prove the workflow.
- [ ] No API keys, passwords, certificates, tokens, private endpoints, or other secrets belong in manifests, examples, fixtures, or docs.
- [ ] Any user-facing UI can be built with native SwiftUI, system controls, Settings, sheets, menus, commands, toolbars, focused values, and SF Symbols.
- [ ] Disabling the extension can remove its contribution cleanly.

Good ideas can be ambitious. The first shipped step should still preserve
Cribble's local-first, preview-before-mutation, reader-first Mac defaults.
