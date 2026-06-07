---
aliases: [research review, literature review, source review, decision review]
keywords: [research, review, evidence, claims, decisions, sources, intelligence]
tags: [demo, research, workflow]
---
# Research Review

Use this note as a small pattern for reviewing research, customer interviews,
legal notes, design references, or any folder where evidence matters.

## Goal

Turn scattered notes into a reviewable brief without losing the source trail.

## Folder shape

```text
Research/
  Interviews/
  Articles/
  Decisions.md
  Open Questions.md
  .cribble/
    extensions/
      review-actions/
        cribble-extension.json
```

## Review loop

1. Search for the topic in plain language.
2. Open likely notes and highlight evidence.
3. Drop bookmarks at sections that need follow-up.
4. Ask Cribble AI for a claim table from the current note.
5. Run Project Intelligence when you need a folder-wide glossary, timeline, or contradiction report.
6. Publish the final brief as Markdown only after reviewing the generated artifact.

## Useful quick action

This is a good first extension because it is data-only and easy to inspect:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.review-actions",
  "name": "Review Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds evidence-review prompts for research folders.",
  "runtime": "declarative",
  "trust": {
    "developerName": "Example Research Team",
    "signingIdentifier": "com.example.cribble.review-actions",
    "teamIdentifier": "ABCDE12345",
    "sourceURL": "https://example.com/review-actions"
  },
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "claim-table",
      "title": "Claim table",
      "icon": "checklist",
      "prompt": "Extract the claims in the current note. For each claim, list the evidence, confidence, and what would change your mind."
    }
  ]
}
```

## Remote runner decision

Use local intelligence for private first passes. Consider a trusted remote runner
only when the folder is too large, the model must be larger, or the same team
runner should process many projects. The preflight should make that choice
obvious before content leaves your Mac.

## Output checklist

- [ ] Every conclusion links to a note or highlighted source.
- [ ] Open questions are separated from decisions.
- [ ] Contradictions are named instead of smoothed over.
- [ ] Remote runner use is intentional and documented.
- [ ] The final artifact is plain Markdown.

← Back to [[Workflow Playbook]] · [[Extensions and Remote Intelligence]] · [[README|Home]]
