# Cribble 1.4.0 — 🥷 Night Shift

Night Shift is a quieter, faster, more Mac-native Cribble.

This release is about making the app feel easier to remember: smaller surfaces,
cleaner shortcuts, fewer scary AI moments, and better handoffs before anything
gets written to your notes.

## ✨ The Feel

Cribble now gets out of the way faster.

- The first screen is tighter and less busy.
- DemoNotes are no longer crowding the launch surface.
- The empty sidebar is smaller and more practical.
- The welcome view focuses on real work: open folder, new note, today, tasks.
- Existing DemoNotes still live in Help when you want the guided tour.

## ⌨️ Shortcuts You Can Actually Remember

The main shortcuts are now simple single keys while you are reading:

| Key | Action |
| --- | --- |
| `←` / `→` | Back / Forward |
| `S` | Search files |
| `O` | Outline |
| `I` | Intelligence window |
| `C` | AI chat |
| `N` | Add note to hovered highlight / New note |
| `T` | Open Tasks |
| `E` | Open current file in your editor |
| `L` | AI Link Notes |
| `R` | Reading Trail |
| `Space` | Focus mode |
| `F` | Reveal current file in Finder |
| `H` | Highlight selected text |
| `B` | Drop or resume a bookmark |
| `Esc` | Exit highlight mode / close overlays |

Copy shortcuts are simpler too:

| Shortcut | Action |
| --- | --- |
| `Command M` | Copy current note as Markdown |
| `Command L` | Copy current note as a Markdown link |
| `Command W` | Copy current note as a wiki link |
| `Command I` | Import |
| `Command N` | Open today's note |

Small case: press `S`, search, click back into the reader, then press `N`, `R`,
or `C`. Search focus now releases properly instead of trapping your keyboard.

## 🧠 Safer Intelligence

AI is still review-first.

- Empty AI diff previews now explain that no safe patch was received.
- Nothing is written unless you approve it.
- Project Intelligence makes local vs remote runner boundaries clearer.
- VPS/team OpenAI-compatible runners get explicit review text before note
  context leaves your Mac.
- Secrets stay in Keychain, not manifests, notes, docs, or diagnostics.

Small case: if AI Link Notes returns no patch, Cribble now says that directly
instead of leaving you in a vague review sheet.

## 🧭 Better Handoffs

Cribble now gives you more useful copy-before-write paths:

- README starters
- Reading Trail starters and summaries
- Search miss handoffs
- Missing slash-command ideas
- Diagnostics and next actions
- Diff copies for teammate review
- Project Intelligence artifact copies
- Extension/import/remote-runner review templates

Small case: if a folder has no README, copy a starter before asking AI to fill
anything. If a search misses, copy the search handoff before clearing it.

## 🧩 Extension Groundwork

This is the first serious extension/plugin foundation, but intentionally safe.

- API v1 stays declarative.
- First extension versions should be read-only.
- Least access and least writing are required.
- User-facing extension UI must stay native SwiftUI/system-control based.
- Import lanes and remote runner profiles are reviewable before execution.
- Executable plugins are still deferred until signing, sandboxing, permissions,
  revocation, audit trails, and native consent are real.

Good ideas can be ambitious. First PRs should still be small and safe.

## ⚡ Performance And Polish

- Large folders use less memory by loading note bodies on demand.
- More generated dependency/tool-cache folders are skipped.
- DemoNotes refresh to the new shortcut language on existing installs.
- The app opens into a calmer, denser workspace.

## ✅ Install Confidence

This DMG is:

- Developer ID signed
- notarized by Apple
- stapled
- Gatekeeper accepted
- universal: Apple Silicon + Intel
- macOS 15+

Download `Cribble-1.4.0.dmg`, open it, and drag Cribble into Applications.

Your notes, highlights, bookmarks, settings, and local caches are not changed by
replacing the app.

## 🥷 Why "Night Shift"?

Because this release came from the kind of pass that makes a product feel better
without making it louder: smaller controls, calmer onboarding, sharper keyboard
memory, and safer intelligence.
