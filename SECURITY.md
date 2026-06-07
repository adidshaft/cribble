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
- proof-of-concept files or logs, if they do not expose private data;
- whether the issue involves a note folder, extension manifest, remote runner,
  renderer/import lane, AI model, diagnostic report, or release package.

You can expect an initial acknowledgement within a reasonable maintainer
window. If the issue is confirmed, fixes and disclosure timing will be handled
case by case.

## Areas of interest

Security-sensitive areas include:

- folder access and security-scoped bookmarks;
- Markdown, Mermaid, image, math, and rich content rendering;
- link handling and external URL opening;
- AI prompts, CLI execution, and generated diff previews;
- declarative extension manifests, permission validation, disabled-state
  filtering, and future plugin trust decisions;
- remote intelligence runner configuration, trust labels, endpoint/model
  consent, Keychain-backed API keys, and revocation behavior;
- importer and renderer declarations, especially any path traversal, unexpected
  network use, or hidden execution behavior;
- release packaging, signing, notarization, and update metadata;
- storage of highlights, bookmarks, preferences, and diagnostics.

## Data posture

Cribble does not operate a server for user documents and does not include
analytics. Optional AI workflows are user-initiated and should preserve the
preview-before-mutation boundary. If a report involves third-party AI tools or
external services, please identify which provider and configuration were used.

Diagnostic reports are intended for support handoff and should avoid secrets.
They may include folder counts, extension ids, manifest summaries, permissions,
runner host labels, and redacted configuration state. Please remove private note
content, API keys, tokens, passwords, private endpoints, certificates, and
signing credentials from any report or attachment you send.

## Extension and remote-runner reports

For extension or plugin-related reports, include the manifest if it is safe to
share, plus the copied extension details from Settings. Do not include Keychain
entries, API keys, private runner URLs, private certificates, or proprietary note
content. Useful details include:

- extension id, kind, runtime, permissions, and enabled/disabled state;
- whether the extension is user-level or project-local;
- which contribution lane is involved: quick action, remote runner, renderer, or
  importer;
- whether disabling the extension removes the risky behavior;
- whether a non-loopback remote runner was approved, and which endpoint host,
  model id, and trust label were shown.

API v1 extensions are declarative and must not execute scripts or binaries. A
report showing hidden execution, unreviewed source-note writes, secret material
in manifests, project-wide reads without explicit consent, or remote calls that
bypass the native review sheet should be treated as security-sensitive.
