---
aliases: [workflow, playbook, team workflows, research workflow]
keywords: [workflow, research, review, team, intelligence, import, extensions]
tags: [demo, workflow]
---
# Workflow Playbook

Cribble works best when it stays calm while your folder gets more ambitious.
This playbook shows three real ways to use the same Markdown library, from a
single reader to a team with extensions and remote intelligence.

## 1. Read, mark, return

Use this flow for articles, specs, meeting notes, and long research files.

1. Open a folder.
2. Highlight a sentence that changes what you think.
3. Press **B** where you want to resume later.
4. Follow two wiki links.
5. Press **P** and use the Reading Trail to reconstruct how you got there.

Try it here:

- Open [[Getting Started]].
- Jump to [[Feature Tour]].
- Return here from the Reading Trail.

## 2. Turn messy notes into a working brief

Use this flow when a folder has scattered decisions, tasks, and references.

1. Search for a fuzzy idea, not just a filename.
2. Open **Project Intelligence** and read the preflight before starting.
3. Generate a glossary, timeline, or contradiction report.
4. Send useful checkboxes to Reminders, Calendar, or `Tasks.md`.
5. Ask Cribble AI to create a short index note for the files you mention.

Useful prompts:

```text
What decisions are repeated across these notes?
```

```text
Create a one-page project brief from @README @Tasks and Intelligence @Feature Tour.
```

For a more evidence-heavy version of this flow, open [[Research Review]].

## 3. Add team conventions without app code

Use this flow when a folder should carry its own tools.

1. Create `.cribble/extensions/your-extension/cribble-extension.json`.
2. Start with a quick action for a repeat prompt.
3. Add a renderer alias if your team uses custom fence names.
4. Add an import lane for future exports, chat logs, or research bundles.
5. Keep remote runners explicit and store secrets in Keychain, not manifests.

See [[Extensions and Remote Intelligence]] for copy-ready manifests.

## When to use remote intelligence

Local-first should be the default. A remote VPS or team runner makes sense when:

- a folder is too large for your laptop;
- the model must be bigger than local memory allows;
- a team needs the same model and prompt policy;
- the runner is controlled by you or your organization.

Before using a remote runner, confirm the URL, model, trust label, and what data
will leave the Mac in the Project Intelligence preflight.

## What good feels like

The product should stay boring in the right places:

- menus are disabled when actions are unavailable;
- refreshes keep unchanged note metadata warm;
- extension manifests are readable before they do anything;
- secrets live in Keychain;
- every generated artifact can be inspected as Markdown.

That is the center of Cribble: a native reader that can become a workbench
without making beginners carry the complexity.

← Back to [[README|Home]] · next: [[Research Review]] · [[Extensions and Remote Intelligence]]
