# Cribble 1.4.0 — Night Shift

Night Shift is a calm, practical release: fewer hard-to-remember shortcuts,
better first-minute guidance, safer AI handoffs, and a clearer path for people
who want to extend Cribble without giving up its local-first Mac feel.

## What feels different

- **One-key navigation for daily work.** Use `N` for a new note, `C` for AI chat,
  `S` for Search files, `R` for Reading Trail, `T` for Tasks, `O` for Outline,
  `I` for Project Intelligence, `L` for AI Link Notes, and Space for Focus Mode.
- **Search behaves naturally.** `S` puts the cursor in Search files; clicking
  back into the reader releases that focus so reading shortcuts work again.
- **Bookmarks are smarter.** `B` drops a bookmark when there is none, and resumes
  the current note's saved bookmark when one exists.
- **Copy shortcuts are easier.** `Command M` copies the current note as Markdown,
  `Command L` copies a Markdown link, and `Command W` copies a wiki link.
- **Today's note stays one gesture away.** `Command N` opens or proposes today's
  `Daily/YYYY-MM-DD.md` note through the same review-first flow.

## Safer intelligence

- Empty AI diff previews now explain that Cribble did not receive a safe patch
  and that nothing was written.
- Project Intelligence has clearer trust checklists for local, VPS, and team
  OpenAI-compatible runners.
- Remote-runner setup keeps secrets in Keychain and makes the data boundary
  visible before note context leaves the Mac.
- AI-generated note changes still go through preview/review/cancel.

## Better onboarding

- DemoNotes now teach the new shortcut language directly.
- The starter checklist points users toward Tasks, Search Handoffs, Reading
  Trail starters, Project Intelligence, and extension contribution without
  requiring them to know the whole app first.
- Reading Trail, search misses, README starters, diagnostics, diffs, and AI
  artifacts all have copyable handoffs for sharing context before creating or
  changing files.

## Extension groundwork

- Cribble now has a stricter, clearer contribution path for extensions/plugins.
- First versions should be declarative and read-only.
- Extension ideas should use least access, least writing, clean disable behavior,
  and native SwiftUI/system-control surfaces.
- Import lanes and remote runner profiles are discoverable through Settings and
  review templates while executable plugins remain intentionally deferred.

## Performance and polish

- Large folders stay lighter by loading note bodies on demand.
- Generated dependency and tool-cache folders are skipped more aggressively.
- DemoNotes refresh to the new shortcut guide on existing installs.

## Installation

This release is packaged as a signed and notarized macOS DMG for macOS 15+.
Download the DMG, open it, and drag Cribble into Applications. If you already
have Cribble installed, replace the existing app.

Your notes, highlights, bookmarks, settings, and local caches are not changed by
the app replacement.
