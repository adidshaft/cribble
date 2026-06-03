# Cribble Roadmap

Cribble's roadmap is maintainer-led. Contributors are welcome to suggest ideas,
but roadmap placement is not a promise that a feature will ship, and accepted
direction may change as the product evolves.

## Current direction

Cribble is focused on being a calm, local-first macOS reader for Markdown
folders, with rich rendering, safe AI-assisted workflows, and a clear boundary
between reading in Cribble and editing in the user's chosen editor.

Important product principles:

- local-first by default;
- reader-first rather than an in-app Markdown editor;
- plain Markdown files remain portable;
- AI or generated changes use preview-before-mutation flows;
- official releases and product direction remain maintainer-controlled.

## Near-term contribution areas

Good open-source contribution areas include:

- reproducible bug fixes;
- Markdown rendering edge cases;
- wiki-link and relative-link behavior;
- tests and fixtures;
- accessibility improvements;
- diagnostics and support workflows;
- documentation and release-support copy;
- provider or integration ideas that have been discussed first.

## Product ideas and larger features

Please start with GitHub Discussions or an issue before implementing:

- major UX changes;
- new AI behavior;
- storage or write-policy changes;
- monetization or distribution changes;
- module extraction and public API design;
- new provider protocols or headless tooling.

Related planning docs:

- `docs/cribble-open-source-plan.md`
- `docs/cribble-intelligence-plan.md`
- `docs/ollama-integration-plan.md`

## Future possibilities

These are directions under consideration, not commitments:

- deeper local AI workflows;
- cleaner provider extension points;
- better architecture documentation;
- focused SwiftPM module extraction;
- richer diagnostics for support and security reports;
- more accessible reading and navigation surfaces.
