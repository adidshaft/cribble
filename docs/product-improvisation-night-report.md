# Product Improvisation Night Report

Date: 2026-06-08
Branch: `codex/product-improvisation-night`

## Executive summary

This branch turned Cribble from a fast Markdown reader with AI experiments into
a broader, safer Mac-native knowledge workspace. The highest-signal gains are:

- **Safer extensibility:** a declarative extension framework with validation,
  Settings visibility, project-local manifests, remote-runner profiles, renderer
  aliases, importer lanes, contributor guidance, and strict API v1 safety
  boundaries before executable plugin code exists.
- **Remote intelligence with consent:** OpenAI-compatible local/VPS/team runner
  profiles are visible, reviewable, redacted in diagnostics, and gated before
  non-loopback extension runners can process notes.
- **Beginner-to-power-user onboarding:** DemoNotes, Help, Settings, Welcome,
  and Chat HUD now expose practical paths for basics, tasks, research review,
  team extensions, remote intelligence, daily notes, and Markdown handoff.
- **More native Mac workflows:** File/Help/View/AI commands now cover New Note,
  Today, Import, Open Tasks, Copy Markdown, Copy Wiki Link, diagnostics, and
  guide recovery with disabled states and familiar shortcuts.
- **Performance and supportability:** no-op refreshes reuse metadata, render
  cache survives stable content, semantic indexing skips identical inputs, and
  diagnostic reports now include a scannable health summary plus refresh,
  intelligence, and extension state.

The product signal is strongest in four areas: safe extension authoring, trusted
remote intelligence, everyday capture/handoff, and recoverable onboarding. Those
areas now have app surfaces, docs, DemoNotes, tests, and copied-review/diagnostic
handoffs instead of living only as ideas.

## Product signal map

| Signal | What users can do now | Why it matters |
| --- | --- | --- |
| Extensions | Create/read/review declarative manifests, project examples, quick actions, remote runners, renderer aliases, and import lanes | Opens a plugin ecosystem without sacrificing local-first trust |
| Remote intelligence | Use local or trusted OpenAI-compatible runners with Keychain credentials, consent, and diagnostics redaction | Lets advanced users use VPS/team GPUs while keeping context boundaries visible |
| First-minute onboarding | Open DemoNotes, role-based guides, recent notes, opened folders, New Note, Today, and Copy Markdown from native surfaces | Makes Cribble useful before users understand the whole product |
| Daily work | Capture `Daily/YYYY-MM-DD.md`, collect Tasks, copy Markdown/wiki links, resume recent notes, and use Chat HUD commands | Broadens beyond “reader” into daily knowledge workflow |
| Maintainer support | Copy reports with health summary, refresh metrics, intelligence state, extension state, and crash report presence | Speeds debugging and extension review without leaking secrets |

## Current branch shape

- Recent commits include native Today/New Note workflows, Help guide recovery,
  Settings extension starter rules, diagnostic health summary, daily chat quick
  action, recent-note welcome shortcuts, and extension idea templates.
- Full-suite validation has passed multiple times during the branch; the latest
  full run after the native New Note/Today work was `214 XCTest + 41 Swift
  Testing`, 0 failures. Later focused suites passed for each subsequent slice.
- Known residual noise: intermittent CoreData XPC messages from the macOS test
  environment during broad runs. These have not failed tests.
- Intentionally not done: executable plugin runtime, signed bundle loading, or
  hidden extension execution. API v1 remains declarative until a sandboxed,
  signed, revocable trust model is ready.

## What changed

### Extension foundation

Cribble now has a concrete, safe foundation for plugins/extensions:

- `cribble-extension.json` manifests with `apiVersion`, reverse-DNS ids, typed extension kinds, typed permissions, optional homepage, explicit runtime mode, and safe relative entrypoints.
- Discovery from the user's Application Support extension folder.
- Discovery from each opened folder's `.cribble/extensions` directory.
- Settings UI for installed extensions, load warnings, permissions, location, enable/disable state, and starter manifest creation across quick actions, remote runners, renderer aliases, and import lanes.
- Installed extension rows can reveal their manifest in Finder, making the declarative system easier to inspect and debug.
- Duplicate id handling, with project-local extensions taking precedence over user-level extensions.
- Data-only quick action contributions that merge enabled extension prompts into the Chat HUD empty state and `/` slash palette.
- Chat HUD empty state now gives installed extension quick actions their own visible section instead of hiding them behind the built-in action limit.
- Data-only intelligence provider profiles that add OpenAI-compatible runner presets to the Intelligence HUD, including remote-runner warnings.
- A Project Intelligence preflight sheet in the HUD before starting folder/all-folder scans, summarizing scope, local vs remote processing, disk/cache expectations, and performance mode.
- The same preflight confirmation now guards sidebar/context-menu Project Intelligence starts, so quick entry points are safer too.
- The Project Intelligence preflight now names remote runner endpoints, selected models, and extension trust labels before scanning notes, making VPS/team-runner decisions more explicit.
- Extension-provided remote runner profiles now show a compact handoff strip in the Intelligence HUD with trust/source details and a copyable endpoint/model/API-key/revocation checklist.
- Manually configured custom remote runners now get the same copyable handoff checklist in the Intelligence HUD, covering endpoint, model, context boundary, Keychain secret handling, review, and revocation.
- A richer empty state that lets new users open a Markdown folder, open the bundled DemoNotes tour, or reset DemoNotes to a clean sandbox.
- The welcome screen now offers role-oriented DemoNotes entry points for Basics, Workflows, Research, and Extensions, helping beginners and power users start from the right mental model.
- The empty reader now shows already-open folders with note counts and one-click README/first-note landing, so returning users can resume from a restored workspace without digging through the sidebar or menus.
- File now includes New Note (`Command-N`) for the active folder. It creates an `Untitled.md` proposal through the same review/apply sheet used by AI and trail-generated notes, avoiding silent disk writes and filename clobbering.
- The Chat HUD now surfaces a visible context receipt after each send, showing how many sources were included or limited and offering copyable details for trust/debugging.
- Extension registry coverage for user/project scans, project-over-user duplicate precedence, warnings, and disabled extension filtering.
- Cleaned up a SQLite vector-binding compiler warning so verification output stays easier to read.
- Updated MLX cache-limit setup to the current `Memory.cacheLimit` API, removing the deprecation warning from focused builds.
- Data-only renderer and importer contribution declarations, with Settings summaries and validation that keeps each contribution under its matching extension kind.
- Enabled renderer extensions can now map declared fence languages onto existing built-in renderers, so teams can make aliases like `workflow` render through Mermaid without executable plugin code.
- Enabled importer extensions now surface as Settings import lanes with file-type and output-format summaries, making future conversion workflows discoverable before any converter execution exists.
- Import lanes in Settings now have a copy-review action with accepted files, output format, declarative runtime status, and the reads/writes/network/secrets/disable-behavior review checklist.
- File menu now includes Import, filtered by enabled importer lanes, to match files to declarative import capabilities before converter execution exists.
- API v1 now makes the extension safety boundary explicit with `"runtime": "declarative"` and rejects executable runtimes until a signed trust model exists.
- Cached sidebar note previews by URL and modification date, so repeated hover previews avoid rereading and preprocessing note bodies.
- Full folder refresh now prunes the reader render cache by stable note content hash instead of clearing every rendered note, keeping unchanged notes warm after single-file external edits.
- Remote Intelligence runner API keys can be entered in the HUD and stored in Keychain; manifests and defaults keep only non-secret profile metadata/URL markers.
- DemoNotes home now includes a checklist-style tour that exercises highlights, bookmarks, zoom, trails, chat, Intelligence preflight, extensions, and search.
- DemoNotes home now also guides beginners through the new review-first New Note flow and Copy Markdown handoff, making ordinary note creation/export part of the first-minute tour.
- DemoNotes AI onboarding now consistently uses the native `Command J` chat shortcut and the bundled demo version was bumped so installed DemoNotes refresh.
- Help menu now exposes Open/Reset DemoNotes Tour, so onboarding is recoverable after users add their own folders.
- Help and the empty welcome screen now expose the Workflow Playbook directly, giving new users a faster route into practical reader, research, team, and remote-runner flows.
- Help now exposes the Team Extension Kit directly, making the extension/plugin design guide recoverable outside Settings.
- Help and the welcome screen now expose the Remote Intelligence guide directly, making VPS/team-runner setup discoverable as a first-class onboarding path.
- DemoNotes now include a `Workflow Playbook` that explains practical flows for reading, project brief creation, team extension conventions, and trusted remote intelligence use.
- DemoNotes now include a `Research Review` workflow for evidence-heavy folders, claim tables, source trails, extension quick actions, and intentional remote-runner use.
- DemoNotes now include a `Team Extension Kit` that turns extension design into a practical team workflow: folder layout, four extension lanes, manifest review checklist, remote-runner policy, and a starter quick action.
- DemoNotes now explain the latest extension authoring affordances directly: Create Project Example, Check Again, copied extension details, and note-row Copy Wiki Link handoff.
- DemoNotes now include a remote-runner handoff checklist for endpoint ownership, model id, trust label, note context, Keychain entry, and revocation.
- DemoNotes now teach the stricter API v1 extension permission map, extension quick-action context limits, and the native remote-runner approval sheet before non-loopback extension profiles are used.
- DemoNotes and the public extension guide now explain that copied diagnostic reports include extension install/enabled state, validation warnings, permissions, and contribution titles for support or PR handoffs without copying Keychain secrets.
- Seeded Project Intelligence artifacts for DemoNotes now match the current tour, including Tasks and Intelligence, Workflow Playbook, Research Review, Team Extension Kit, and Extensions and Remote Intelligence.
- The bundled DemoNotes version has been bumped so existing demo installs refresh to the improved onboarding content.
- File > Import now stays discoverable even before import lanes exist: it opens a guided setup sheet that can create a project-local or user-level importer example, open extension Settings, or jump to the Team Extension Kit.
- File now includes Copy Markdown (`Command-Option-Shift-M`) for the selected note, giving users a native Mac handoff path into chat, email, issue trackers, and other Markdown tools without revealing paths or creating wiki links.
- The diff preview sheet now labels brand-new file proposals as “Review New Note” with a “Create Note” action, so manual and AI-generated note creation no longer look like link-edit reviews.
- The Import setup sheet now explains the safe import-lane model as a three-step path: declare file types, review the data-only manifest, and disable the lane cleanly.
- The extension author guide now sketches the trust model required before executable plugins: signed bundles, explicit consent, process isolation, enforced permissions, Keychain-only secrets, revocation, and audit logs.
- Extension manifests can now declare validated trust metadata (`developerName`, `signingIdentifier`, optional Apple Team ID, and source URL), and Settings shows that declared identity while executable runtime remains blocked.
- Cribble now has a local extension trust-decision store for future executable plugin consent/revocation, with Settings controls to revoke or clear remembered trust decisions while API v1 remains data-only.
- Settings now lets extension authors copy a concise manifest review summary for any installed extension, making support threads, PR reviews, and team approval flows easier.
- Settings now has a Check Again action for extension manifests, reloading user/project manifests and surfacing a clear validated/warnings status without leaving the Settings window.
- Settings can now create starter extension manifests directly in the active folder's `.cribble/extensions` directory, making the project-local team workflow actionable from the app.
- Settings now links directly to the Team Extension Kit from the Extensions section, so users can move from manifest controls to the practical guide without hunting through DemoNotes.
- Settings now also links directly to the Remote Intelligence guide from the Extensions section, keeping remote-runner setup guidance beside runner/importer manifest controls.
- Settings now turns the no-extension empty state into direct actions for creating a read-only quick action, creating a project-local example, or opening the Team Extension Kit.
- The public extension guide now includes an open-source contribution checklist for read-only-first behavior, least reading, least writing, no hidden execution, Keychain-only secrets, clean disabling, and native SwiftUI-only UI.
- The public extension guide now adds a first-extension-PR recipe: pick one manifest kind, start from Create Project Example, stay declarative/read-only, include reads/writes/network/secrets/disable behavior, paste copied extension details, and add focused tests for validation/discovery changes.
- The public guide and Team Extension Kit now ask contributors to open with an idea-first proposal: audience, repeated workflow, first read-only surface, data access, network/write needs, and the native SwiftUI review point.
- `SECURITY.md` now covers the new extension and remote-intelligence surfaces explicitly: manifest permissions, disabled-state filtering, Keychain-backed runner keys, diagnostic-report redaction, importer/renderer declarations, and non-loopback runner consent.
- The GitHub pull request template now includes an extension/plugin review section for read scope, writes, network, secrets, disable behavior, native SwiftUI UI, and focused tests/docs.
- Copied extension and import-lane review summaries now include the same contributor safety contract, so PRs and team approvals carry read-only-first, least-read/write, Keychain-only secrets, clean-disable, and native SwiftUI expectations without hunting through docs.
- Extension manifest loading now rejects secret-looking JSON keys and values before decoding, so ignored unknown fields cannot smuggle API keys, bearer tokens, passwords, private keys, authorization headers, or token query strings into `cribble-extension.json`.
- Extension permission validation now enforces the API v1 least-permission map: quick actions may request only current-note reads, remote runners may request only OpenAI-compatible network, renderer/importer declarations cannot request note/network permissions, `read-project-notes` is reserved until consent/scoping semantics exist, and `propose-file-changes` is blocked until preview/review execution exists.
- Extension registry contribution getters now defensively re-check manifest validity before exposing quick actions, runner profiles, renderer aliases, or import lanes, keeping least-permission behavior intact even if a future path bypasses scan-time loading.
- Extension quick actions now run without ambient related-note or Project Intelligence expansion, so a `read-current-note` manifest cannot silently receive broader project context; built-in actions and ordinary chat sends keep the richer workspace-aware behavior.
- Extension-provided non-loopback remote runner profiles now require a one-time native review before the HUD applies them, with endpoint, model, trust label, extension source, Keychain state, context-leaves-Mac warning, and disable path shown before approval.
- Remote runner trust matching now uses endpoint plus model id, and approval keys include profile id, source, endpoint, and model, preventing one extension profile from borrowing another profile's trust or approval.
- Sidebar Project Intelligence starts now reuse the same extension remote-runner approval sheet before enabling a folder, and app restore reloads project extension profiles, presents the same consent sheet when needed, then resumes restore after approval.
- Settings now opens the Extensions section with a compact native dashboard: installed/enabled status, warnings, and lane counts for quick actions, remote runners, renderers, and importers, so beginners and power users can see extension health at a glance.
- The extension dashboard now counts active lanes only, so disabled remote runners, importers, renderers, or quick actions no longer look available in the summary.
- The app now treats `Command-F` as a native Find in Files shortcut that focuses the toolbar search field, with a Clear Search command for fast recovery.
- Back/Forward and Clear Search menu commands now mirror real app state, so Mac menus disable when there is no history or search text to act on.
- Sidebar search now shows a clear “No Matches” recovery state with a Clear Search action instead of implying the folder has no Markdown files.
- Sidebar search now also shows a compact success summary when matches exist, including visible file-result counts, semantic related-result counts, and a Clear action directly above the file tree.
- Semantic search reindexing now skips exact repeat document sets by comparing a stable path/content-hash signature before touching the embedding engine, so no-op refreshes avoid needless indexing churn.
- Folder refresh now reuses prior `MarkdownDocumentMeta` for unchanged files based on path, modification time, and file size, so no-op or single-file refreshes avoid reparsing every note body while still rebuilding the sidebar tree.
- `LinkIndex` can now build from metadata, including frontmatter aliases, tags, keywords, headings, titles, and relative paths, which keeps wiki-link resolution intact when unchanged files skip full loading.
- Diagnostics now record refresh reuse counts when unchanged note metadata is reused, making performance wins visible in copied reports without changing normal status text.
- Diagnostic reports now include a Latest Refresh section with duration, total Markdown files, loaded vs reused metadata, skipped/failed counts, and render-cache pruning, so large-folder smoothness is measurable in support reports.
- The Diagnostics sheet now shows the latest refresh performance as a scannable summary above the full report, and refresh status text includes duration plus reused metadata counts.
- Diagnostic reports now include Project Intelligence state: scope, provider, redacted runner URL, Keychain credential marker, model, performance mode, queue depth, indexed files, stale artifacts, last activity, resource gate, and model download progress.
- Diagnostic reports now include Extension state: installed/enabled counts, warnings, lane counts, installed manifest summaries, permissions, contribution titles, and enabled/disabled status for support and review handoffs.
- Extension diagnostics now separate installed contribution totals from active contribution totals, so disabled lanes are visible but not mistaken for currently available behavior.
- File menu now exposes selected-note Reveal in Finder and Copy File Path actions with Mac-style shortcuts and disabled states, making common file handoff tasks accessible without sidebar context menus.
- File menu now also exposes Copy Wiki Link for the selected note, letting readers hand off `[[Note Title]]` links into notes, chat, task docs, and team workflows without manually retyping titles.
- Markdown file rows in the sidebar now expose Reveal in Finder, Copy File Path, Copy Markdown, and Copy Wiki Link directly in the context menu, using cached metadata for link titles and resilient disk reads for Markdown handoff.
- Toolbar help now matches the Mac-style command shortcuts for Focus Mode, Outline, AI Link Notes, and Cribble AI instead of stale single-key hints.
- The in-reader shortcut popover now includes Find in Files, Import, Copy Markdown, Copy Wiki Link, diagnostics, and the newer Mac-style command chords.
- The Tasks aggregator is now a first-class Mac workflow with File > Open Tasks, `Command-Option-T`, status feedback, and refreshed DemoNotes instructions.
- Task export status now says when a task was collected in `Tasks.md` and sent to Reminders or Calendar, so the in-app tracker and external handoff do not feel like separate invisible actions.
- Reminders/Calendar export permission errors now name the exact System Settings privacy pane to fix, instead of giving a generic access-denied message.
- Chat HUD slash command search now keeps an explicit no-match recovery state with example commands and a Clear action, making built-in and extension commands easier to discover.
- Chat HUD now includes a visible `Extract tasks` quick action and `/tasks` slash command that turns prose into a reviewed `Tasks.md` proposal instead of writing directly, connecting AI help to the native Tasks workflow.
- Reader-only View menu commands now follow the focused document context, disabling bookmark, highlight, and reading-trail actions when no reader can handle them.
- The Intelligence Ask tab now offers starter question chips that adapt to available artifacts, giving new users a faster path from generated context to useful project answers.
- The Intelligence Ask tab now adds a remote-runner privacy starter question when a non-loopback runner is selected, helping users ask what context may leave the Mac before leaning on VPS or team GPU intelligence.
- File > Open Tasks now reports creation/opening failures visibly, including `Tasks.md` directory collisions, instead of showing a false success status.

This is intentionally data-only. Cribble validates and displays extension intent, but does not execute arbitrary extension code yet.

### Demo and onboarding

DemoNotes now include `Extensions and Remote Intelligence.md`, linked from the welcome note. It teaches:

- the extension manifest shape,
- project-local extension folders,
- trusted remote intelligence runners,
- and the intended extension lanes: quick actions, intelligence providers, renderers, and importers.
- copy-ready manifest patterns for quick actions, remote runners, renderer aliases, and import lanes.
- a dedicated `docs/extensions.md` developer guide for extension authors outside the bundled demo library.

The first-run demo now points users toward the product's broader future without hiding the current safety boundary.

### Mac-native keyboard behavior

Global single-letter app shortcuts were replaced with Mac-style modified shortcuts:

- `Command O`: open folder
- `Command R`: refresh
- `Command Option E`: open in editor
- `Command Option O`: outline
- `Command Shift F`: focus mode
- `Command Option L`: AI Link Notes
- `Command Option I`: Project Intelligence
- `Command J`: Cribble AI chat
- `Command Left/Right`: back/forward

Reader-only quick keys (`H`, `B`, `P`, `Esc`) remain handled by the reader context, so typing in search, chat, and sheets is less surprising.

## Product signal

The highest-signal direction is: **Cribble as a calm native reader that can grow into a trustworthy knowledge workbench.**

The branch strengthens that story in three ways:

- beginners get clearer demos and safer defaults,
- power users see an extension path,
- advanced users can imagine trusted remote intelligence without losing the local-first posture.

## Validation

Ran:

```sh
swift test --filter ExtensionManifestTests
swift test --filter 'Extension|RunnerCredentialStoreTests'
swift test
swift test --filter CribbleUITests
swift test --filter 'IntelligencePreflightTests|CribbleUITests'
swift test --filter CribbleUITests
swift test --filter ExtensionRegistryTests
swift test --filter CribbleUITests
swift test --filter SemanticSearchIndexTests
swift test --filter 'LinkIndexTests|SemanticSearchIndexTests|CribbleUITests'
swift test --filter Extension
swift test --filter CribbleUITests
swift test --filter 'LinkIndexTests|CribbleUITests'
swift test --filter CribbleUITests
swift test --filter CribbleUITests
swift test --filter ExtensionRegistryTests
swift test --filter ExtensionRegistryTests
swift test --filter DiagnosticsCenterTests
swift test --filter CribbleUITests
swift test --filter 'LinkIndexTests|CribbleUITests'
swift test --filter ExtensionRegistryTests
swift test --filter CribbleUITests
swift test --filter ChatHUDLogicTests
swift test --filter CribbleUITests
swift test --filter DiagnosticsCenterTests
swift test --filter 'NavigationHistoryTests|CribbleUITests'
swift test --filter IntelligencePreflightTests
swift test --filter CribbleUITests
swift test --filter CribbleUITests
swift test --filter ExtensionRegistryTests
swift test --filter CribbleUITests
swift test --filter CribbleUITests
swift test --filter 'LinkIndexTests|CribbleUITests'
swift test --filter ChatHUDLogicTests
swift test --filter CribbleUITests
swift test --filter IntelligenceEngineTests
swift test --filter CribbleUITests
swift test --filter CribbleUITests
swift test --filter IntelligenceEngineTests
swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts
swift test --filter IntelligenceEngineTests
swift test --filter TaskExporterTests
swift test --filter ExtensionRegistryTests
swift test --filter CribbleUITests
swift test --filter 'LinkIndexTests|CribbleUITests'
swift test --filter DiagnosticsCenterTests
swift test --filter CribbleUITests
swift test --filter ExtensionRegistryTests
swift test --filter ExtensionManifestTests
swift test --filter ExtensionManifestTests
swift test --filter 'ExtensionManifestTests|ExtensionRegistryTests'
swift test --filter ChatHUDLogicTests
swift test --filter IntelligencePreflightTests
swift test --filter 'IntelligencePreflightTests|CribbleUITests'
swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'
swift test --filter ExtensionRegistryTests
swift test --filter CribbleUITests
swift test --filter DiagnosticsCenterTests
swift test
swift test --filter CribbleUITests
swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'
swift test --filter ExtensionRegistryTests
swift test --filter IntelligenceEngineTests
swift test --filter DiagnosticsCenterTests
swift test --filter CribbleUITests
swift test --filter 'ExtensionRegistryTests|CribbleUITests'
```

Latest pass:

- `swift test` passed on 2026-06-08 after the latest extension trust-decision work: 180 XCTest tests, 0 failures.
- The Swift Testing extension/credential suites also passed: 28 tests across manifest, registry, trust-decision, and runner credential coverage.
- `swift test --filter CribbleUITests` passed on 2026-06-08: 11 XCTest tests, 0 failures.
- `swift test --filter SemanticSearchIndexTests` passed on 2026-06-08: 9 XCTest tests, 0 failures.
- `swift test --filter 'LinkIndexTests|SemanticSearchIndexTests|CribbleUITests'` passed on 2026-06-08: 22 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after refresh instrumentation: 11 XCTest tests, 0 failures.
- Latest `swift test --filter Extension` passed on 2026-06-08 after trust declarations: 23 Swift Testing tests, 0 failures.
- Latest `swift test --filter Extension` passed on 2026-06-08 after the trust-decision store: 27 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after selected-note menu actions: 11 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after direct Workflow Playbook entry points: 11 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after Copy Wiki Link: 12 XCTest tests, 0 failures.
- Latest `swift test --filter 'LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after Team Extension Kit DemoNotes work: 14 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after sidebar note context menu actions: 13 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after extension review summaries and Settings validation loop: 8 Swift Testing tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after project-local example creation: 9 Swift Testing tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after refresh diagnostics snapshots: 2 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after refresh diagnostics integration: 14 XCTest tests, 0 failures.
- Latest `swift test --filter 'LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes extension/onboarding updates: 16 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after welcome-screen onboarding entry points: 14 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after Settings linked the Team Extension Kit: 9 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after toolbar shortcut help cleanup: 14 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after Help linked the Team Extension Kit: 14 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligencePreflightTests|CribbleUITests'` passed on 2026-06-08 after remote-runner preflight trust details: 16 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after guided Import setup added project importer example coverage: 10 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after guided Import setup: 14 XCTest tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after visible chat context receipts: 32 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after native Find in Files commands: 14 XCTest tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after visible refresh performance summaries: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'NavigationHistoryTests|CribbleUITests'` passed on 2026-06-08 after stateful Mac menu actions: 15 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08 after extension runner handoff details: 3 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after extension runner handoff UI wiring: 14 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after search empty-state and shortcut-reference polish: 14 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after actionable extension Settings empty state: 10 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after actionable extension Settings empty state: 14 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after the native Open Tasks command: 14 XCTest tests, 0 failures.
- Latest `swift test --filter 'LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes Tasks instructions: 16 XCTest tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after slash command no-match recovery: 33 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after reader-focused menu commands: 14 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceEngineTests` passed on 2026-06-08 after Intelligence Ask starter chips: 25 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after Open Tasks failure reporting: 16 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after Import setup safety-path UI: 16 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceEngineTests` passed on 2026-06-08 after custom remote-runner handoff UI: 25 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after refreshing DemoNotes seeded artifacts: 1 XCTest test, 0 failures.
- Latest `swift test --filter IntelligenceEngineTests` passed on 2026-06-08 after refreshed seeded artifacts: 25 XCTest tests, 0 failures.
- Latest `swift test --filter TaskExporterTests` passed on 2026-06-08 after destination-specific Reminders/Calendar permission messages: 2 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after import-lane review summaries: 10 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after the Settings import-lane copy action: 16 XCTest tests, 0 failures.
- Latest `swift test --filter 'LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes chat shortcut cleanup: 18 XCTest tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after Intelligence diagnostics snapshots: 4 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after wiring Intelligence diagnostics through report entry points: 16 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after copied extension safety contracts: 10 Swift Testing tests, 0 failures.
- Latest `swift test --filter ExtensionManifestTests` passed on 2026-06-08 after manifest secret-material rejection: 19 Swift Testing tests, 0 failures.
- Latest `swift test --filter ExtensionManifestTests` passed on 2026-06-08 after least-permission manifest validation: 25 Swift Testing tests, 0 failures.
- Latest `swift test --filter 'ExtensionManifestTests|ExtensionRegistryTests'` passed on 2026-06-08 after registry-side permission gating: 36 Swift Testing tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after extension quick actions stopped receiving ambient project context: 34 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08 after extension remote-runner consent: 6 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligencePreflightTests|CribbleUITests'` passed on 2026-06-08 after sidebar/restore remote-runner approval gates: 22 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes remote-runner consent refresh: 19 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after the Settings extension dashboard: 11 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after sidebar search success summaries: 17 XCTest tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after extension diagnostics snapshots: 6 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the latest diagnostics and sidebar changes: 201 XCTest tests and 41 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after clearer task export status: 18 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes diagnostic-handoff guidance: 21 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after active-lane extension dashboard counts: 11 Swift Testing tests, 0 failures.
- Latest `swift test --filter IntelligenceEngineTests` passed on 2026-06-08 after remote-runner Ask starter questions: 28 XCTest tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after installed-vs-active extension diagnostics: 6 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after direct Remote Intelligence entry points: 18 XCTest tests, 0 failures.
- Latest `swift test --filter 'ExtensionRegistryTests|CribbleUITests'` passed on 2026-06-08 after Settings Remote Guide entry point: 18 XCTest tests and 11 Swift Testing tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after slash-command discovery and alias ranking: 36 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after welcome-screen folder shortcuts: 20 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after idea-first extension contribution guidance: 23 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after native Copy Markdown command: 21 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the latest Chat HUD, welcome, extension-guide, and native command work: 210 XCTest tests and 41 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after sidebar Copy Markdown handoff: 22 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after native New Note proposals: 23 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|LinkIndexTests|CribbleUITests'` passed on 2026-06-08 after DemoNotes New Note and Copy Markdown onboarding: 26 XCTest tests, 0 failures.
- Docs-only validation on 2026-06-08 confirmed `SECURITY.md` includes extension manifests, remote runners, Keychain/API-key redaction, diagnostic reports, importer/renderer declarations, and hidden execution guidance.
- Latest `swift test --filter CribbleUITests/testNewNoteProposalUsesReviewFlowAndAppliesUniqueFile` passed on 2026-06-08 after adding visible New Note entry points to the sidebar controls and welcome surface: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testNewNoteProposalUsesReviewFlowAndAppliesUniqueFile` passed on 2026-06-08 after clarifying the review sheet subtitle and cancel help for new-note proposals: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|CribbleUITests'` passed on 2026-06-08 after adding the native Today note workflow, sidebar/welcome/menu entry points, nested Daily note creation, and DemoNotes onboarding: 26 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the native New Note and Today note workflows: 214 XCTest tests and 41 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the date-aware Draft today chat quick action and DemoNotes onboarding: 38 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after adding the open-source extension idea proposal template to `docs/extensions.md` and DemoNotes Team Extension Kit: 1 XCTest test, 0 failures. A docs search also confirmed read-only, first read-only version, native Mac surface, and later-not-first-PR checklist language across contributor surfaces.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after adding welcome-screen Continue shortcuts from recent note history, including stale-entry filtering and duplicate suppression: 26 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after adding the native Settings starter-rules strip for extension authors: 12 Swift Testing tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after adding a top-level diagnostic Health Summary that keeps status, refresh, intelligence, extension, and crash-report state scannable without exposing runner secrets: 7 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding direct Help menu entries for Tasks & Intelligence and Research Review onboarding guides: 28 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding a first-screen Tasks onboarding tile to the Welcome Start With grid: 2 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after adding New Note/Today/Open Folder actions to the sidebar empty-folder state: 27 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the recent Daily Chat, extension-authoring, diagnostics, help-menu, welcome, and sidebar-empty-state work: 218 XCTest tests and 42 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the reviewed `Extract tasks` Chat HUD quick action and DemoNotes onboarding: 39 XCTest tests, 0 failures.
- Latest runs built without the previous SQLite vector-binding or MLX cache-limit warnings.

## Next best sections

1. Continue reducing warning noise from broader full-suite builds as new dependency APIs shift.
2. Keep expanding DemoNotes around real team workflows: research review, project intelligence, extension authoring, and import-lane planning.
3. Add signed bundle verification only after the consent/revocation path is fully wired into an executable plugin sandbox.

Note: a first attempt to pass FSEvent changed paths into the store hit a Swift 6.3 compiler crash in sendability analysis, so that risky path was not kept. The committed performance work stays on a stable preview-cache path.
