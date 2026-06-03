# Security Policy

Cribble is a local-first macOS app that opens folders selected by the user,
renders Markdown, stores local reading metadata, and can run optional AI
workflows. Security reports are especially important because users may open
private notes, local source trees, and other sensitive Markdown libraries.

## Supported versions

Security fixes target the latest public release and the current `main` branch.
Older releases may receive guidance, but not every historical version will be
patched.

## Report a vulnerability

Please do not open a public issue for a suspected vulnerability.

Email: `adidshaft@kyokasuigetsu.xyz`

Include as much detail as you safely can:

- affected Cribble version or commit;
- macOS version and hardware;
- steps to reproduce;
- impact and who can trigger it;
- proof-of-concept files or logs, if they do not expose private data.

You can expect an initial acknowledgement within a reasonable maintainer
window. If the issue is confirmed, fixes and disclosure timing will be handled
case by case.

## Areas of interest

Security-sensitive areas include:

- folder access and security-scoped bookmarks;
- Markdown, Mermaid, image, math, and rich content rendering;
- link handling and external URL opening;
- AI prompts, CLI execution, and generated diff previews;
- release packaging, signing, notarization, and update metadata;
- storage of highlights, bookmarks, preferences, and diagnostics.

## Data posture

Cribble does not operate a server for user documents and does not include
analytics. Optional AI workflows are user-initiated and should preserve the
preview-before-mutation boundary. If a report involves third-party AI tools or
external services, please identify which provider and configuration were used.
