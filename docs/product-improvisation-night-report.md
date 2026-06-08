# Product Improvisation Night Report

Date: 2026-06-08
Branch: `codex/product-improvisation-night`

Short version: [`product-improvisation-summary.md`](product-improvisation-summary.md).
Readiness checkpoint:
[`product-improvisation-readiness-checkpoint.md`](product-improvisation-readiness-checkpoint.md).

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
  action, recent-note welcome shortcuts, extension idea templates, and the
  Decision Log workflow.
- Full-suite validation has passed multiple times during the branch; the latest
  full run after the Help command, Decision Log DemoNotes, remote-runner,
  diagnostics, and report work was `235 XCTest + 43 Swift Testing`, 0 failures.
  Later focused suites passed for the native Decision Log entry points.
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
- Remote Project Intelligence preflight now separates the runner details from a visible orange Data Boundary row, explicitly naming prompts, note excerpts, generated summaries, and embedding requests that may leave the Mac.
- Intelligence HUD runner tooltips, inline warnings, and copied handoff checklists now reuse the same precise remote Data Boundary language as preflight and consent.
- Extension-provided remote runner profiles now show a compact handoff strip in the Intelligence HUD with trust/source details and a copyable endpoint/model/API-key/revocation checklist.
- The remote-runner consent sheet now includes Copy Review, letting users paste
  runner, endpoint, model, embedding model, data-boundary, Keychain, source, and
  disable/revoke details into a team thread before approving a VPS/team runner.
- Copied remote-runner reviews now include an approval checklist for endpoint
  ownership, Keychain-only secrets, context fit, and disable-path understanding.
- Manually configured custom remote runners now get the same copyable handoff checklist in the Intelligence HUD, covering endpoint, model, context boundary, Keychain secret handling, review, and revocation.
- A richer empty state that lets new users open a Markdown folder, open the bundled DemoNotes tour, or reset DemoNotes to a clean sandbox.
- The welcome screen now offers role-oriented DemoNotes entry points for Basics, Workflows, Research, and Extensions, helping beginners and power users start from the right mental model.
- The welcome screen now includes a direct Cribble AI DemoNotes tile, making
  summaries, simple explanations, related-note discovery, reviewed index
  creation, and chat onboarding visible from the first screen.
- The first-run Cribble AI engine chooser now shows a data-boundary line for
  every option, distinguishing on-Mac models from Claude/Codex CLI choices that
  send note context through the user's signed-in command-line tool.
- The regular Chat HUD model picker now keeps that boundary visible in each
  model row and tooltip, so users see local-vs-CLI context even after first-run
  onboarding is dismissed.
- The Cribble AI DemoNotes guide now matches the product behavior: local-first
  on-device models are private by default, while Claude/Codex CLI choices are
  opt-in and clearly described as sending note context through the signed-in
  command-line tool.
- DemoNotes Home, Getting Started, and Tasks & Intelligence now use local-first
  AI language instead of absolute on-device/no-cloud claims, while still making
  remote runners opt-in and reviewed before note context leaves the Mac.
- The empty reader now shows already-open folders with note counts and one-click README/first-note landing, so returning users can resume from a restored workspace without digging through the sidebar or menus.
- File now includes New Note (`Command-N`) for the active folder. It creates an `Untitled.md` proposal through the same review/apply sheet used by AI and trail-generated notes, avoiding silent disk writes and filename clobbering.
- Missing wiki-link recovery now creates notes through the same review/apply sheet instead of writing directly, while existing targets still open immediately.
- README and DemoNotes now teach that missing wiki links become review-first
  new-note proposals, so users can safely link before writing without surprise
  file creation.
- The public README now advertises the current native AI menu, extension
  framework, remote runner consent/Keychain posture, and review-first generated
  note proposals instead of only the earlier AI-linking path.
- The Chat HUD now surfaces a visible context receipt after each send, showing how many sources were included or limited and offering copyable details for trust/debugging.
- Built-in Chat HUD quick actions now carry short descriptions in the empty
  state chips and slash-command palette, helping beginners understand what each
  action will do before running it.
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
- DemoNotes home now also guides beginners through the new review-first New Note
  flow, Copy Markdown handoff, and Copy Markdown Link handoff, making ordinary
  note creation/export part of the first-minute tour.
- Empty README panels now offer native starter actions for New Note, Today, and the Tasks Guide beside the AI README-fill action, so a sparse folder gives users multiple useful next steps.
- DemoNotes AI onboarding now consistently uses the native `Command J` chat shortcut and the bundled demo version was bumped so installed DemoNotes refresh.
- Help menu now exposes Open/Reset DemoNotes Tour, so onboarding is recoverable after users add their own folders.
- Help now exposes the Cribble AI guide directly, making the AI menu/chat
  onboarding recoverable after users leave the welcome screen.
- Help and the empty welcome screen now expose the Workflow Playbook directly, giving new users a faster route into practical reader, research, team, and remote-runner flows.
- Help now exposes the Team Extension Kit directly, making the extension/plugin design guide recoverable outside Settings.
- Help and the welcome screen now expose the Remote Intelligence guide directly, making VPS/team-runner setup discoverable as a first-class onboarding path.
- DemoNotes now include a `Workflow Playbook` that explains practical flows for reading, project brief creation, team extension conventions, and trusted remote intelligence use.
- DemoNotes now include a `Research Review` workflow for evidence-heavy folders, claim tables, source trails, extension quick actions, and intentional remote-runner use.
- DemoNotes now include a `Team Extension Kit` that turns extension design into a practical team workflow: folder layout, four extension lanes, manifest review checklist, remote-runner policy, and a starter quick action.
- DemoNotes now explain the latest extension authoring affordances directly: Create Project Example, Check Again, copied extension details, and note-row Copy Wiki Link handoff.
- DemoNotes now include a remote-runner handoff checklist for endpoint ownership, model id, trust label, note context, Keychain entry, and revocation.
- DemoNotes now teach the stricter API v1 extension permission map, extension quick-action context limits, and the native remote-runner approval sheet before non-loopback extension profiles are used.
- DemoNotes now point extension authors to Settings > Extensions > Copy Proposal
  so idea-first extension review starts from the same template used by GitHub
  issues and contributor docs.
- DemoNotes and the public extension guide now explain that copied diagnostic reports include extension install/enabled state, validation warnings, permissions, and contribution titles for support or PR handoffs without copying Keychain secrets.
- Seeded Project Intelligence artifacts for DemoNotes now match the current tour, including Tasks and Intelligence, Workflow Playbook, Research Review, Team Extension Kit, and Extensions and Remote Intelligence.
- The bundled DemoNotes version has been bumped so existing demo installs refresh to the improved onboarding content.
- File > Import now stays discoverable even before import lanes exist: it opens a guided setup sheet that can create a project-local or user-level importer example, open extension Settings, or jump to the Team Extension Kit.
- File now includes Copy Markdown (`Command-Option-Shift-M`) for the selected note, giving users a native Mac handoff path into chat, email, issue trackers, and other Markdown tools without revealing paths or creating wiki links.
- File and sidebar note menus now include Copy Markdown Link, producing a
  portable `[Title](relative/path.md)` handoff with escaped titles and encoded
  nested paths for GitHub, email, docs, and chat.
- Copy Markdown Link now has a native shortcut (`Command-Option-Shift-K`) and
  appears in the in-reader shortcut popover plus DemoNotes shortcut table.
- The diff preview sheet now labels brand-new file proposals as “Review New Note” with a “Create Note” action, so manual and AI-generated note creation no longer look like link-edit reviews.
- The Import setup sheet now explains the safe import-lane model as a three-step path: declare file types, review the data-only manifest, and disable the lane cleanly.
- The extension author guide now sketches the trust model required before executable plugins: signed bundles, explicit consent, process isolation, enforced permissions, Keychain-only secrets, revocation, and audit logs.
- Extension manifests can now declare validated trust metadata (`developerName`, `signingIdentifier`, optional Apple Team ID, and source URL), and Settings shows that declared identity while executable runtime remains blocked.
- Cribble now has a local extension trust-decision store for future executable plugin consent/revocation, with Settings controls to revoke or clear remembered trust decisions while API v1 remains data-only.
- GitHub now includes an Extension proposal issue template that asks for the
  first read-only version, data contract, native Mac surface, later-not-first-PR
  scope, least access, preview-before-write, secrets, and clean disable behavior
  before implementation starts.
- Extension issue and PR templates now make the native UI condition explicit:
  first versions should not need web views, custom chrome, Electron-style panels,
  or non-native UI without maintainer approval.
- Settings Extensions now includes Copy Proposal, giving contributors a native
  way to copy the same idea-first, read-only-first extension proposal template
  before writing implementation code.
- The in-app Copy Proposal template now mirrors the hard native UI guard from
  GitHub: first versions should not require web views, custom chrome,
  Electron-style panels, or non-native UI without maintainer approval.
- Help now includes `Open Extension Settings` beside the extension and remote
  intelligence guides, giving users a native jump from learning about manifests
  to managing them.
- Settings now lets extension authors copy a concise manifest review summary for any installed extension, making support threads, PR reviews, and team approval flows easier.
- Settings now has a Check Again action for extension manifests, reloading user/project manifests and surfacing a clear validated/warnings status without leaving the Settings window.
- Settings can now create starter extension manifests directly in the active folder's `.cribble/extensions` directory, making the project-local team workflow actionable from the app.
- Settings now links directly to the Team Extension Kit from the Extensions section, so users can move from manifest controls to the practical guide without hunting through DemoNotes.
- Settings now also links directly to the Remote Intelligence guide from the Extensions section, keeping remote-runner setup guidance beside runner/importer manifest controls.
- Settings now turns the no-extension empty state into direct actions for creating a read-only quick action, creating a project-local example, or opening the Team Extension Kit.
- The public extension guide now includes an open-source contribution checklist for read-only-first behavior, least reading, least writing, no hidden execution, Keychain-only secrets, clean disabling, and native SwiftUI-only UI.
- The public extension guide now adds a first-extension-PR recipe: pick one manifest kind, start from Create Project Example, stay declarative/read-only, include reads/writes/network/secrets/disable behavior, paste copied extension details, and add focused tests for validation/discovery changes.
- The public guide and Team Extension Kit now ask contributors to open with an idea-first proposal: audience, repeated workflow, first read-only surface, data access, network/write needs, and the native SwiftUI review point.
- The public guide and Team Extension Kit proposal blocks now ask whether
  non-native UI is needed and require maintainer approval if a first version
  cannot stay native SwiftUI/system-control based.
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
- Settings can now copy a whole Extension Dashboard summary with installed/enabled counts, warning counts, active lanes, and the read-only/least-access/native-SwiftUI safety contract for issues and extension PR review.
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
- Markdown file rows in the sidebar now expose Reveal in Finder, Copy File Path,
  Copy Markdown, Copy Markdown Link, and Copy Wiki Link directly in the context
  menu, using cached metadata for link titles and resilient disk reads for
  Markdown handoff.
- Toolbar help now matches the Mac-style command shortcuts for Focus Mode, Outline, AI Link Notes, and Cribble AI instead of stale single-key hints.
- The in-reader shortcut popover now includes Find in Files, Import, Copy Markdown, Copy Wiki Link, diagnostics, and the newer Mac-style command chords.
- The Tasks aggregator is now a first-class Mac workflow with File > Open Tasks, `Command-Option-T`, status feedback, and refreshed DemoNotes instructions.
- Opening Tasks now distinguishes first creation from existing-file opens with
  `Created Tasks.md` vs `Opened Tasks`, making the native task workflow less
  ambiguous.
- Task export status now says when a task was collected in `Tasks.md` and sent to Reminders or Calendar, so the in-app tracker and external handoff do not feel like separate invisible actions.
- Reminders/Calendar export permission errors now name the exact System Settings privacy pane to fix, instead of giving a generic access-denied message.
- Chat HUD slash command search now keeps an explicit no-match recovery state with example commands and a Clear action, making built-in and extension commands easier to discover.
- Chat HUD now includes a visible `Extract tasks` quick action and `/tasks` slash command that turns prose into a reviewed `Tasks.md` proposal instead of writing directly, connecting AI help to the native Tasks workflow.
- Chat HUD empty-state and no-match hints now advertise the live command count and newer `/tasks` and `/daily` commands, making the slash palette easier to recover from.
- The AI menu now exposes `Summarize Current Note`, opening the Chat HUD directly into the built-in summary prompt and disabling when no note is selected.
- The AI menu now also exposes `Explain Current Note Simply` and `Find Related Notes`, turning beginner comprehension and next-note discovery into native commands instead of hidden prompts.
- The AI menu now exposes `Create Index Note`, opening the Chat HUD into the
  reviewed `index.md` proposal flow so messy folders can get a map from a
  native command.
- The AI menu now exposes `Extract Tasks from Current Note`, opening the Chat HUD directly into the reviewed `Tasks.md` proposal flow and disabling when no note is selected.
- The AI menu now also exposes `Draft Today with AI`, giving daily capture a native menu entry that still routes through the reviewed `Daily/YYYY-MM-DD.md` proposal flow.
- The AI menu is grouped into linking/chat, reading help, capture/tasks, and project intelligence sections so the expanded native surface stays scannable.
- The in-reader shortcut popover now includes an AI Menu section that names the
  native Summarize, Explain, Find Related, Create Index, Draft Today, and
  Extract Tasks commands.
- The main `ContentView` controller setup was extracted from the long SwiftUI modifier chain, reducing type-checker pressure as more native commands are added.
- The main window focused command setup is now split into primary, diagnostics, navigation, and help groups, keeping the expanded Mac command surface easier for Swift to type-check.
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
- Latest `swift test --filter 'CribbleUITests/testCopySelectedDocumentMarkdownLinkUsesTitleAndFileName|CribbleUITests/testCopyMarkdownLinkForURLUsesRelativeEncodedPath|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding Copy Markdown Link to File/sidebar handoff surfaces and DemoNotes onboarding: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testCopySelectedDocumentMarkdownLinkUsesTitleAndFileName|CribbleUITests/testCopyMarkdownLinkForURLUsesRelativeEncodedPath|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after assigning `Command-Option-Shift-K` to Copy Markdown Link and updating shortcut onboarding: 3 XCTest tests, 0 failures.
- Docs-only validation on 2026-06-08 confirmed `SECURITY.md` includes extension manifests, remote runners, Keychain/API-key redaction, diagnostic reports, importer/renderer declarations, and hidden execution guidance.
- Latest `swift test --filter CribbleUITests/testNewNoteProposalUsesReviewFlowAndAppliesUniqueFile` passed on 2026-06-08 after adding visible New Note entry points to the sidebar controls and welcome surface: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testNewNoteProposalUsesReviewFlowAndAppliesUniqueFile` passed on 2026-06-08 after clarifying the review sheet subtitle and cancel help for new-note proposals: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|CribbleUITests'` passed on 2026-06-08 after adding the native Today note workflow, sidebar/welcome/menu entry points, nested Daily note creation, and DemoNotes onboarding: 26 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the native New Note and Today note workflows: 214 XCTest tests and 41 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the date-aware Draft today chat quick action and DemoNotes onboarding: 38 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after adding the open-source extension idea proposal template to `docs/extensions.md` and DemoNotes Team Extension Kit: 1 XCTest test, 0 failures. A docs search also confirmed read-only, first read-only version, native Mac surface, and later-not-first-PR checklist language across contributor surfaces.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after aligning the public guide and Team Extension Kit proposal blocks with the hard native UI exception question: 1 XCTest test, 0 failures. A docs search confirmed the same native/no-web-view/custom-chrome guard across docs and GitHub templates.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after adding welcome-screen Continue shortcuts from recent note history, including stale-entry filtering and duplicate suppression: 26 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after adding the native Settings starter-rules strip for extension authors: 12 Swift Testing tests, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests` passed on 2026-06-08 after adding a top-level diagnostic Health Summary that keeps status, refresh, intelligence, extension, and crash-report state scannable without exposing runner secrets: 7 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding direct Help menu entries for Tasks & Intelligence and Research Review onboarding guides: 28 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding a first-screen Tasks onboarding tile to the Welcome Start With grid: 2 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after adding New Note/Today/Open Folder actions to the sidebar empty-folder state: 27 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the recent Daily Chat, extension-authoring, diagnostics, help-menu, welcome, and sidebar-empty-state work: 218 XCTest tests and 42 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the reviewed `Extract tasks` Chat HUD quick action and DemoNotes onboarding: 39 XCTest tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after polishing command count and no-match hints: 38 XCTest tests, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after promoting task extraction to the native AI menu and refreshing DemoNotes wording: 39 XCTest tests, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after promoting Draft Today to the native AI menu and extracting controller setup from the main SwiftUI modifier chain: 39 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08 after adding copied Extension Dashboard summaries for contributor/support handoff: 12 Swift Testing tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08 after splitting remote-runner Data Boundary details into a visible preflight row: 6 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08 after unifying Intelligence HUD runner warnings and copied handoffs around the same precise Data Boundary language: 6 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after adding native New Note, Today, and Tasks Guide actions to the empty README panel: 27 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests` passed on 2026-06-08 after routing missing wiki-link note creation through the review/apply sheet: 28 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after refreshing README/DemoNotes onboarding for review-first missing wiki-link creation: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after promoting Summarize to the native AI menu and splitting the focused command setup for faster type-checking: 39 XCTest tests, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after promoting Explain Simply and Find Related to native AI menu commands: 39 XCTest tests, 0 failures.
- Full `swift test` passed on 2026-06-08 after the latest native AI menu and onboarding work: 220 XCTest tests and 42 Swift Testing tests, 0 failures. The run still prints intermittent CoreData XPC noise from the macOS test environment, but it does not fail tests.
- Latest `swift test --filter ChatHUDLogicTests/testCatalogHasDefaultAndUniqueIDs` passed on 2026-06-08 after grouping the expanded AI menu: 1 XCTest test, 0 failures.
- Docs-only validation on 2026-06-08 confirmed the new Extension proposal issue
  template plus `CONTRIBUTING.md` and `docs/extensions.md` mention read-only
  first versions, data contracts, least note access, native SwiftUI surfaces,
  later-not-first-PR scope, and clean disable behavior.
- Docs-only validation on 2026-06-08 confirmed extension issue and PR templates
  now mention native SwiftUI plus no web views, custom chrome, Electron-style
  panels, or non-native UI.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after
  adding short descriptions to built-in Chat HUD quick actions and slash-command
  rows: 39 XCTest tests, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after promoting Create Index Note to the native AI menu and refreshing DemoNotes onboarding: 40 XCTest tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after
  adding first-run engine chooser data-boundary labels for local and cloud CLI
  choices: 40 XCTest tests, 0 failures.
- Latest `swift test --filter ChatHUDLogicTests` passed on 2026-06-08 after
  carrying the same data-boundary copy into the regular Chat HUD model picker:
  40 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testCribbleAIGuideNamesModelDataBoundaries|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after correcting the Cribble AI DemoNotes guide to describe on-device versus Claude/Codex CLI data boundaries: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testCribbleAIGuideNamesModelDataBoundaries|CribbleUITests/testDemoNotesUseLocalFirstAICopy|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after aligning DemoNotes Home, Getting Started, and Tasks & Intelligence with local-first/opt-in remote AI copy: 3 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08
  after adding copyable remote-runner consent review summaries: 8 XCTest tests,
  0 failures.
- Latest `swift test --filter IntelligencePreflightTests` passed on 2026-06-08
  after adding the remote-runner approval checklist to copied consent reviews:
  8 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes` passed on 2026-06-08 after adding the AI Menu section to the in-reader shortcut popover: 1 XCTest test, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08
  after adding the Settings Copy Proposal extension template: 13 Swift Testing
  tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests` passed on 2026-06-08
  after bringing the in-app Copy Proposal template in line with the hard native
  UI guard: 13 Swift Testing tests, 0 failures.
- Latest `swift test --filter IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts` passed on 2026-06-08 after teaching DemoNotes about Settings > Extensions > Copy Proposal: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes` passed on 2026-06-08 after adding Cribble AI to the welcome Start With grid: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'ExtensionRegistryTests|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes'` passed on 2026-06-08 after the Settings proposal, DemoNotes handoff, and Welcome AI entry work: 2 XCTest tests and 13 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes` passed on 2026-06-08 after adding the Help > Open Cribble AI Guide entry: 1 XCTest test, 0 failures.
- Docs-only validation on 2026-06-08 confirmed `README.md` mentions the native
  AI menu commands, `cribble-extension.json`, trusted local/VPS/team runners,
  and review-first generated note proposals.
- Latest `swift test --filter 'CribbleUITests/testOpenTasksCreatesAndSelectsTasksFile|CribbleUITests/testAddToTasksAnchorsSourceAndDeduplicatesBacklink'` passed on 2026-06-08 after clarifying first-time Tasks creation status and tightening isolated store setup in the focused UI tests: 2 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes` passed on 2026-06-08 after expanding the Help-menu bundle guard to every direct guide entry: Cribble AI, Workflow Playbook, Tasks and Intelligence, Research Review, Team Extension Kit, and Extensions and Remote Intelligence.
- Latest `swift test --filter CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes` passed on 2026-06-08 after adding Help > Open Extension Settings and rebuilding the native command surface: 1 XCTest test, 0 failures.
- Product-copy sweep on 2026-06-08 aligned the App Store unlock sheet,
  first-run engine chooser, toolbar help, and Intelligence preview release note
  around local-first AI with explicit data boundaries instead of absolute
  no-cloud claims.
- Remote-runner handoffs on 2026-06-08 now copy the same approval checklist
  used by consent reviews, covering endpoint ownership, Keychain-only secrets,
  context fit, and the disable path before note context can leave the Mac.
- Settings > Extensions copied dashboard summaries now include practical next
  steps for contributors: fix warnings, start with project-local examples, keep
  v1 read-only/reviewed, and gate remote runners behind data-boundary review.
- The first-screen welcome now includes a native Copy Starter Checklist action
  for sharing the recommended tour order: basics, AI model boundary, Tasks,
  workflow playbook, extension proposal, native/read-only guardrails, and remote
  runner review.
- DemoNotes Home, Feature Tour, and Cribble AI now use the same local-first
  model-boundary language for Pathfinder and generic intelligence, replacing
  older on-device shorthand where Claude/Codex choices may also appear.
- Copied diagnostic reports now include next-action guidance for intelligence
  and extensions, including missing remote-runner Keychain credentials,
  extension manifest warnings, empty extension setups, queued jobs, and stale
  artifacts.
- The Diagnostic Report sheet now surfaces those intelligence/extension next
  actions in a native summary strip above the full report, so recovery steps are
  visible before users copy or file an issue.
- Help now includes Copy Starter Checklist, making the first-run tour order
  available as a native command even after users have opened real folders.
- The File > Import setup sheet now includes Copy Review for pre-install import
  lane proposals, making the no-execution, user-selected-files, previewed-writes,
  no-secrets, native-SwiftUI, and clean-disable boundaries shareable before a
  manifest is created or adapted.
- DemoNotes now describe the current extension surface as data-only lanes:
  quick actions, remote runner profiles, renderer aliases, and import-lane
  declarations, replacing vaguer "future automation" language.
- Intelligence artifact readers now include Copy Markdown, letting generated
  project indexes, reports, summaries, and diagrams move into issues, PRs, or
  notes with type/path/saved-status metadata attached.
- Intelligence Ask answers now include Copy Answer, preserving the original
  question plus answer text for notes, issues, PRs, and team review threads.
- DemoNotes now teach the new Project Intelligence handoffs: Copy Markdown for
  generated artifacts and Copy Answer for Ask responses with the question
  attached.
- The public README now mentions Project Intelligence Markdown/Ask answer
  handoffs, keeping the repo overview aligned with the app and DemoNotes.
- Contributor-facing extension docs and the Team Extension Kit now point
  importer authors to File > Import > Copy Review before creating or adapting a
  manifest, so the pre-install no-execution, selected-file, previewed-write,
  no-secret, native-SwiftUI, and clean-disable contract is visible in proposal
  threads.
- Help now includes Copy Extension Proposal, reusing the Settings proposal
  template as a native command so contributors can start an idea-first,
  read-only-first extension proposal without opening Settings first.
- The first-run checklist, DemoNotes home, and Team Extension Kit now teach the
  Help > Copy Extension Proposal route alongside Settings > Extensions > Copy
  Proposal, keeping onboarding aligned with the native command.
- Help now includes Copy Remote Runner Setup Review, a generic VPS/team-runner
  approval template covering endpoint/model/trust, data boundary, Keychain-only
  secrets, retention/logging/access-control review, and revoke paths before a
  runner is configured.
- DemoNotes home, the Team Extension Kit, the remote-intelligence guide, and the
  first-run checklist now teach Help > Copy Remote Runner Setup Review as the
  starting point before sharing or enabling VPS/team runners.
- Intelligence diagnostics now avoid false Keychain recovery advice for
  localhost/local-runner endpoints without credentials, while non-loopback
  remote runners still ask users to store credentials in Keychain or switch back
  to on-device processing.
- DemoNotes now include a `Decision Log` workflow for lightweight team decision
  records with status, owner, context, evidence, follow-up tasks, and review
  boundary prompts; the bundled DemoNotes version was bumped so existing demo
  installs refresh.
- Help and the welcome screen now expose Decision Log directly, giving users a
  native route into decision/rationale capture without hunting through DemoNotes.
- Help now includes Copy Decision Entry Template, backed by a reusable
  `DecisionLogTemplate.markdown`, so users can start a decision record directly
  from the macOS menu and then compare it with the DemoNotes example.
- Help now includes Copy Research Review Template, backed by a reusable
  `ResearchReviewTemplate.markdown`, giving evidence-heavy folders a native
  starting point for claim tables, gaps, recommendations, and review boundaries.
- `docs/extension-contributions.md` now gives open-source contributors a
  dedicated extension on-ramp: ideas can be ambitious, while first PRs stay
  read-only, least-reading, least-writing, no-hidden-execution, cleanly
  disableable, Keychain-safe, and hard native SwiftUI. README, CONTRIBUTING,
  docs index, the manifest reference, and Team Extension Kit all point to it.
- Help now includes Open Extension Contribution Guide, backed by a bundled
  DemoNotes note and refreshed seeded demo intelligence, so contributors can
  review read-only, least-writing, hard-native-SwiftUI rules inside the app.
- The welcome Start With grid now includes Contribute, opening the Extension
  Contribution Guide directly for extension authors and open-source contributors.
- `docs/product-improvisation-readiness-checkpoint.md` now captures the
  keep/stop/defer guidance for this branch, including explicit stop conditions
  around executable plugins, hidden execution, broad reads, source-note writes,
  secrets, non-native extension UI, and opaque remote intelligence.
- Help now includes Copy Product Readiness Checkpoint, backed by a reusable
  `ProductReadinessCheckpointTemplate.markdown`, so the keep/stop/defer framing
  can move into PRs, releases, and maintainer handoffs.
- Help menu actions are now grouped into clearer native sections for DemoNotes,
  guides, extension settings, copyable templates, diagnostics, and GitHub
  actions, reducing menu scan cost as the onboarding surface grows.
- Copied extension review summaries now separate the open-source contribution
  guide from the manifest reference, so pasted PR/team handoffs point people to
  the strict read-only, least-writing, native-SwiftUI rules first and the schema
  details second.
- Help now includes Copy Import Lane Setup Review, sharing the same importer
  safety checklist as File > Import > Copy Review. Public docs, DemoNotes, Team
  Extension Kit, and the starter checklist all point importer authors to that
  native Help path before any converter runtime exists.
- The bundled Extension Contribution Guide, Team Extension Kit checklist,
  Decision Log, and manifest reference now all prefer Help > Copy Import Lane
  Setup Review while keeping File > Import > Copy Review as the in-sheet
  alternate; the bundled DemoNotes version was bumped so installed demos refresh.
- Settings > Extensions now links directly to the Extension Contribution Guide,
  so extension authors can move from installed manifests and example creation to
  the strict read-only, least-writing, hard-native-SwiftUI rules without leaving
  the native settings surface.
- The in-reader Shortcuts popover now includes a compact Help Menu section for
  recovering DemoNotes, opening contribution/remote-intelligence guides, copying
  starter/research/decision/import/runner reviews, and diagnostics/reporting.
- Remote-runner handoff strips in the Intelligence HUD now show a visible
  Copy Review label, instead of relying on an icon-only control, so custom VPS
  and extension-provided runner review details are easier to discover.
- Extension diagnostic next actions now point new manifest authors to Settings >
  Extensions plus Contribution Guide, and tell disabled-extension users to copy
  proposal/review details before enabling, making support reports double as safe
  recovery instructions.
- Extension diagnostic reports now include exact review routes for Contribution
  Guide, Copy Extension Proposal, Copy Import Lane Setup Review, and Copy Remote
  Runner Setup Review, so copied support reports can become actionable handoffs.
- The Settings > Extensions Copy Summary handoff now includes the same native
  review routes, so extension dashboard summaries can move directly into issues,
  PRs, or team chats without losing the safety path.
- The product summary and readiness checkpoint now treat copied diagnostics and
  Settings summaries with exact native review routes as explicit product signal,
  keeping the stop/go report aligned with the support handoff work.
- README and CONTRIBUTING now name the native extension contribution routes:
  Settings > Extensions > Contribution Guide, Help > Copy Extension Proposal,
  Help > Copy Import Lane Setup Review, and Help > Copy Remote Runner Setup
  Review, so new contributors can start from either docs or the app.
- The first-run welcome launchpad now exposes Tasks beside New Note and Today
  after a folder is open, turning the empty reader into a faster work surface
  for project task capture without requiring users to remember the shortcut.
- Settings > Extensions now also offers the Contribution Guide directly from
  the no-extension empty state, so first-time authors can read the read-only
  safety contract before creating a starter manifest.
- The sidebar empty state now mirrors the first-run launchpad: no-folder users
  can open the Demo Tour immediately, while opened empty folders offer Tasks
  beside New Note and Today.
- Sidebar search now explains filename misses more clearly: related semantic
  results remain visible with copy that says so, and empty folders with no
  related hits can open Project Intelligence directly to index deeper search.
- Settings now has a native Project Intelligence section for performance mode,
  battery-saver pausing, chat context use, disk budget, and local/remote runner
  boundary guidance, making advanced intelligence tuning discoverable without
  opening the HUD first.
- Reading Trail's empty state now offers a Workflow Guide action and, when a
  folder is open, New Note, turning the trail panel into a useful first-use
  path for research and reading workflows.
- Missing wiki-link screens now include Copy Wiki Link, so users can hand off
  `[[Missing Note]]` to chat, tasks, or another note without creating the file
  immediately.
- Pathfinder now includes Copy Summary, producing a portable Markdown handoff
  with source, target, existing wiki path, conceptual bridge, and any generated
  explanation for research notes, issues, or team review.
- The Outline panel's no-heading state now offers Copy Heading Starter, giving
  new authors a small Markdown scaffold instead of leaving the navigation panel
  passive.
- Chat HUD's empty state now surfaces the extension contribution lane when no
  extension slash commands are installed, pointing users from everyday chat into
  the Help > Open Extension Contribution Guide path without hiding the built-in
  quick actions.
- The File > Import setup sheet now links directly to the Extension Contribution
  Guide, so importer authors can move from starter manifest creation to the
  strict read-only, least-writing, native SwiftUI contribution rules without
  detouring through Help or Settings.
- The diff review sheet now includes Copy Diff, letting users export an
  AI-generated patch to an issue, PR, or teammate before applying it to notes;
  the renderer also covers empty-diff handoff text.
- Task checkbox menus now include Copy Task, giving users a zero-permission
  handoff path for action items before choosing Cribble Tasks, Reminders, or
  Calendar export.
- Diagnostic Report now has Copy Next Actions, letting users share only the
  actionable intelligence/extension/debug checklist when a full report is too
  heavy.
- Extension starter manifests now generate a neighboring `README.md` with
  read-only, least-permission, previewed-write, Keychain, native SwiftUI, and
  review-route guidance, while preserving contributor edits on repeat creation.
- DemoNotes now points users to Copy Task, Copy Diff, and Diagnostics > Copy
  Next Actions in the relevant tour steps, making the newer lightweight handoff
  paths easier to discover.
- Settings > Extensions now tells authors that starter examples include a README
  review checklist, matching the generated files and making the safer package
  visible before creation.
- Settings > Extensions > Copy Summary now also names the generated starter
  README checklist, so contributors can paste one review handoff that includes
  manifest scope, review routes, and the local checklist artifact.
- Settings > Extensions creation feedback now confirms that examples were
  created with a README checklist, closing the loop immediately after authors
  use Create Example or Create Project Example.
- Reading Trail now includes Copy Trail Summary, a zero-file Markdown handoff
  for research paths, highlights, and dwell-time context when users want to
  share progress before creating a permanent note.
- The shortcut popover and starter checklist now mention Copy Trail Summary, so
  first-run users can discover the zero-file research handoff before committing
  a trail note.
- The macOS Help menu now exposes Copy Reading Trail Summary when the reader is
  active, giving the zero-file research handoff a native command route alongside
  the other review templates.
- Reading Trail panel copies now also update the app status with "Copied reading
  trail summary", matching the new menu command and making the handoff feel
  confirmed from either native route.
- Folder scanning now skips more generated/tool-cache directories including
  `.gradle`, `.terraform`, `.turbo`, `coverage`, and `vendor`, reducing large
  code-folder traversal and avoiding starter README writes in dependency caches.
- Settings > Extensions validation warnings now include Copy Warnings, producing
  a pasteable review checklist with exact warning text, Check Again guidance,
  and the strict contribution-guide route.
- Diagnostic extension reports now name Settings > Extensions > Copy Warnings
  as the warning handoff route, so copied support reports and contributor
  reviews point to the same validation-sharing action.
- DemoNotes now teach extension authors to use Settings > Extensions > Copy
  Warnings before editing invalid manifests, keeping the contribution guide,
  Team Extension Kit, Settings, and diagnostics aligned.
- Generated extension starter READMEs now also list Settings > Extensions > Copy
  Warnings, so each starter folder carries the same validation handoff beside
  its manifest.
- Settings > Extensions now confirms enabled/disabled extension toggles in the
  status strip, making contribution state changes visible just like copy,
  create, and validation actions.
- Settings > Extensions now also confirms future executable-plugin trust revoke
  and clear actions in the status strip, so trust-state changes are visible.
- Settings > Extensions now confirms user extension folder and manifest Reveal
  actions in the status strip, keeping Finder handoffs visible like copy and
  toggle actions.
- Settings > Project Intelligence now includes Copy Review beside Remote Guide,
  so VPS/team-runner setup can be copied for review from the same native place
  users tune performance, disk budget, and the remote data boundary.
- Project Intelligence preflight now offers Copy Review when a remote runner is
  selected, letting users paste folder scope, endpoint/model/trust, context
  boundary, performance mode, Keychain-secret expectations, and revocation
  prompts before starting a VPS/team intelligence run.
- Extensions and Remote Intelligence now shows a paste-ready Remote Runner Setup
  Review example inline, so VPS/team-runner users can see endpoint ownership,
  data boundary, retention/logging, Keychain, and disable checks before enabling
  anything.
- `docs/extensions.md` now defines executable-plugin readiness gates: signed
  bundle identity, process isolation, Cribble-mediated permissions, native
  consent, previewed writes, Keychain-only secrets, revocation, audit trails, and
  native UI. DemoNotes and Decision Log point contributors back to that gate list
  while API v1 remains declarative.
- Latest `swift test --filter CribbleUITests/testImportLaneSetupReviewKeepsExecutionBoundariesClear` passed on 2026-06-08 after adding Import setup Copy Review: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after clarifying current extension lanes in DemoNotes: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligenceEngineTests/testArtifactHandoffMarkdownIncludesReviewMetadataAndBody|IntelligenceEngineTests/testAskHandoffMarkdownIncludesQuestionAndAnswer'` passed on 2026-06-08 after adding Intelligence artifact and Ask answer Markdown handoffs: 2 XCTest tests, 0 failures.
- Latest combined `swift test --filter 'CribbleUITests/testImportLaneSetupReviewKeepsExecutionBoundariesClear|CribbleUITests/testDemoNotesUseLocalFirstAICopy|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts|IntelligenceEngineTests/testArtifactHandoffMarkdownIncludesReviewMetadataAndBody|IntelligenceEngineTests/testAskHandoffMarkdownIncludesQuestionAndAnswer'` passed on 2026-06-08 after the newest import, DemoNotes, and Intelligence handoff work: 5 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoNotesUseLocalFirstAICopy` passed on 2026-06-08 after teaching contributor docs and the Team Extension Kit to use File > Import > Copy Review for importer proposals: 1 XCTest test, 0 failures. A docs search confirmed Copy Review, user-selected files, previewed writes, native SwiftUI, and clean-disable language across the contributor surfaces.
- Latest `swift test --filter ExtensionRegistryTests/extensionProposalTemplateCopiesIdeaFirstSafetyContract` passed on 2026-06-08 after adding the Help > Copy Extension Proposal command: 1 Swift Testing test, 0 failures. A source search confirmed the focused command, Help menu item, pasteboard action, and shared proposal template wiring.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour'` passed on 2026-06-08 after aligning DemoNotes and the first-run checklist with Help > Copy Extension Proposal: 2 XCTest tests, 0 failures.
- Latest `swift test --filter IntelligencePreflightTests/testRemoteRunnerSetupReviewNamesConsentAndRevocation` passed on 2026-06-08 after adding Help > Copy Remote Runner Setup Review: 1 XCTest test, 0 failures. A source search confirmed the focused command, Help menu item, pasteboard action, data-boundary wording, Keychain-secret guidance, and retention/logging/access-control review prompt.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour'` passed on 2026-06-08 after teaching DemoNotes and the first-run checklist to start VPS/team-runner setup with Help > Copy Remote Runner Setup Review: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'DiagnosticsCenterTests/testIntelligenceSnapshotDoesNotRequestKeychainForLocalRunnerWithoutCredential|DiagnosticsCenterTests/testIntelligenceSnapshotRecommendsKeychainForRemoteRunnerWithoutCredential|DiagnosticsCenterTests/testIntelligenceSnapshotFormatsRunnerWithoutSecrets'` passed on 2026-06-08 after tightening local-vs-remote runner diagnostic next actions: 3 XCTest tests, 0 failures.
- Latest combined `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour|IntelligencePreflightTests/testRemoteRunnerSetupReviewNamesConsentAndRevocation|DiagnosticsCenterTests/testIntelligenceSnapshotDoesNotRequestKeychainForLocalRunnerWithoutCredential|DiagnosticsCenterTests/testIntelligenceSnapshotRecommendsKeychainForRemoteRunnerWithoutCredential|ExtensionRegistryTests/extensionProposalTemplateCopiesIdeaFirstSafetyContract'` passed on 2026-06-08 after the Help command, DemoNotes, and diagnostics polish: 5 XCTest tests and 1 Swift Testing test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes|CribbleUITests/testDemoNotesUseLocalFirstAICopy|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding Decision Log to DemoNotes, seeded artifacts, and the bundled refresh version: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes|CribbleUITests/testDemoNotesUseLocalFirstAICopy'` passed on 2026-06-08 after adding the Help > Open Decision Log Guide command and welcome Decisions tile: 2 XCTest tests, 0 failures. A source search confirmed the focused command, ContentView handler, and tile route to `Decision Log.md`.
- Latest `swift test --filter 'ExtensionRegistryTests/extensionGuideDocumentsExecutableReadinessGates|CribbleUITests/testDemoNotesUseLocalFirstAICopy'` passed on 2026-06-08 after adding executable plugin readiness gates to the public extension guide, Team Extension Kit, and Decision Log: 1 XCTest test and 1 Swift Testing test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour|CribbleUITests/testDecisionLogTemplateNamesReviewBoundary'` passed on 2026-06-08 after adding Help > Copy Decision Entry Template and the shared Decision Log template: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour|CribbleUITests/testResearchReviewTemplateNamesEvidenceAndBoundaries'` passed on 2026-06-08 after adding Help > Copy Research Review Template and the shared Research Review template: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'ExtensionRegistryTests/openSourceExtensionContributionGuideKeepsFirstPRsStrict|CribbleUITests/testDemoNotesUseLocalFirstAICopy'` passed on 2026-06-08 after adding the standalone open-source extension contribution guide and Team Extension Kit links: 1 XCTest test and 1 Swift Testing test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes|CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the bundled Extension Contribution Guide and Help menu route: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testWelcomeStartGridIncludesContributorPath|CribbleUITests/testDemoNotesUseLocalFirstAICopy|IntelligenceJobsTests/testDemoSeederSeedsExampleArtifacts'` passed on 2026-06-08 after adding the welcome Contribute tile: 3 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/productImprovisationReadinessCheckpointNamesStopConditions` passed on 2026-06-08 after adding the branch readiness checkpoint: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testProductReadinessCheckpointTemplateNamesStopConditions|ExtensionRegistryTests/productImprovisationReadinessCheckpointNamesStopConditions'` passed on 2026-06-08 after adding Help > Copy Product Readiness Checkpoint: 1 XCTest test and 1 Swift Testing test, 0 failures.
- Latest `swift test --filter CribbleUITests/testHelpMenuGroupsGuidesTemplatesAndDiagnostics` passed on 2026-06-08 after grouping the Help menu into native sections: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'ExtensionRegistryTests/installedExtensionReviewSummaryIncludesManifestDetails|ExtensionRegistryTests/extensionDashboardSummaryCountsInstalledLanesAndWarnings'` passed on 2026-06-08 after separating contribution guide and manifest-reference links in copied extension reviews: 2 Swift Testing tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testHelpMenuGroupsGuidesTemplatesAndDiagnostics|CribbleUITests/testImportLaneSetupReviewKeepsExecutionBoundariesClear|CribbleUITests/testDemoNotesUseLocalFirstAICopy|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour'` passed on 2026-06-08 after exposing Help > Copy Import Lane Setup Review and moving the importer checklist to shared templates: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'IntelligencePreflightTests/testProjectIntelligencePreflightReviewCopiesScopeAndBoundary|IntelligencePreflightTests/testRemoteRunnerSummaryIncludesEndpointModelAndTrustLabel|IntelligencePreflightTests/testRemoteRunnerSetupReviewNamesConsentAndRevocation'` passed on 2026-06-08 after adding Copy Review to remote Project Intelligence preflight: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDemoNotesUseLocalFirstAICopy|ExtensionRegistryTests/extensionGuideDocumentsExecutableReadinessGates|ExtensionRegistryTests/openSourceExtensionContributionGuideKeepsFirstPRsStrict'` passed on 2026-06-08 after aligning the bundled contribution guide, Team Extension Kit, Decision Log, and public manifest reference with Help > Copy Import Lane Setup Review: 1 XCTest test and 2 Swift Testing tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testExtensionSettingsLinksToContributionGuide|CribbleUITests/testHelpMenuGroupsGuidesTemplatesAndDiagnostics'` passed on 2026-06-08 after adding the Settings > Extensions Contribution Guide button: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testShortcutPopoverSurfacesHelpRecoveryPaths|CribbleUITests/testWelcomeStartGridIncludesContributorPath'` passed on 2026-06-08 after adding Help Menu recovery paths to the in-reader Shortcuts popover: 2 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testRemoteRunnerHandoffStripsExposeCopyReviewLabels` passed on 2026-06-08 after labeling Intelligence HUD runner handoff copy actions as Copy Review: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'DiagnosticsCenterTests/testExtensionSnapshotFormatsInstalledLanesAndWarnings|DiagnosticsCenterTests/testExtensionSnapshotSuggestsReviewForDisabledExtensions|DiagnosticsCenterTests/testDiagnosticReportIncludesExtensionSnapshot'` passed on 2026-06-08 after improving extension diagnostics next actions for new manifests and disabled extensions: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'DiagnosticsCenterTests/testExtensionSnapshotFormatsInstalledLanesAndWarnings|DiagnosticsCenterTests/testDiagnosticReportIncludesExtensionSnapshot'` passed on 2026-06-08 after adding exact extension review routes to copied diagnostics: 2 XCTest tests, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/extensionDashboardSummaryCountsInstalledLanesAndWarnings` passed on 2026-06-08 after adding native review routes to Settings > Extensions Copy Summary: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/productImprovisationReadinessCheckpointNamesStopConditions` passed on 2026-06-08 after updating the summary/readiness checkpoint to name diagnostics and Settings summary review routes: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/topLevelContributorDocsNameNativeExtensionReviewRoutes` passed on 2026-06-08 after adding native extension review routes to README and CONTRIBUTING: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testWelcomeLaunchpadIncludesProjectTaskLane|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour|CribbleUITests/testWelcomeStartGridIncludesContributorPath'` passed on 2026-06-08 after adding the welcome Tasks launchpad action: 3 XCTest tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after adding the Contribution Guide action to the Extensions empty state: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testSidebarEmptyStateOffersDemoTourAndTaskLane|CribbleUITests/testWelcomeLaunchpadIncludesProjectTaskLane'` passed on 2026-06-08 after adding Demo Tour and Tasks actions to the sidebar empty state: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testSidebarEmptySearchHintGuidesSemanticAndIntelligenceRecovery|CribbleUITests/testSidebarNoMatchEmptyStateOffersProjectIntelligenceRecovery|CribbleUITests/testSidebarSearchSummaryCountsNestedFileMatches'` passed on 2026-06-08 after adding sidebar search recovery copy and a Project Intelligence recovery action: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testSettingsExposeProjectIntelligenceControls|CribbleUITests/testExtensionSettingsLinksToContributionGuide'` passed on 2026-06-08 after adding the native Project Intelligence Settings section: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testReadingTrailEmptyStateOffersWorkflowRecovery|CribbleUITests/testDemoHelpGuideTargetsExistInBundledNotes'` passed on 2026-06-08 after adding recovery actions to the Reading Trail empty state: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testUnresolvedTargetCanCopyMissingWikiLink|CribbleUITests/testUnresolvedCreateUsesReviewFlowAndOpensExistingFile'` passed on 2026-06-08 after adding Copy Wiki Link to the missing-note screen: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'PathfinderTests|CribbleUITests/testPathfinderSheetCanCopySummary'` passed on 2026-06-08 after adding Copy Summary to Pathfinder: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testOutlineEmptyStateCanCopyHeadingStarter|CribbleUITests/testShortcutPopoverSurfacesHelpRecoveryPaths'` passed on 2026-06-08 after adding Copy Heading Starter to the Outline empty state: 2 XCTest tests, 0 failures.
- Latest `swift test --filter 'ChatHUDLogicTests/testExtensionLaneSummaryGuidesEmptyAndInstalledStates|ChatHUDLogicTests/testSlashCommandsMatchExtensionSourceName|ChatHUDLogicTests/testExtensionQuickActionsSuppressAmbientContext|CribbleUITests/testChatEmptyStateSurfacesExtensionContributionLane'` passed on 2026-06-08 after adding the Chat HUD extension contribution empty-state lane: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testImportGuidanceSheetLinksContributionGuide|CribbleUITests/testImportLaneSetupReviewKeepsExecutionBoundariesClear|CribbleUITests/testDemoNotesUseLocalFirstAICopy'` passed on 2026-06-08 after adding the Contribution Guide route to the Import setup sheet: 3 XCTest tests, 0 failures.
- Latest `swift test --filter 'UnifiedDiffTests|CribbleUITests/testDiffPreviewSheetCanCopyPatchForReview|CribbleUITests/testPathfinderSheetCanCopySummary'` passed on 2026-06-08 after adding Copy Diff to the review sheet and a reusable diff renderer: 8 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testTaskMenuCanCopyTaskWithoutExternalExport|CribbleUITests/testTaskExternalExportStatusNamesTasksAndDestination|TaskExporterTests'` passed on 2026-06-08 after adding Copy Task to checkbox menus: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testDiagnosticsSheetCanCopyNextActionsOnly|DiagnosticsCenterTests/testDiagnosticReportIncludesExtensionSnapshot|DiagnosticsCenterTests/testExtensionSnapshotFormatsInstalledLanesAndWarnings|DiagnosticsCenterTests/testIntelligenceSnapshotRecommendsKeychainForRemoteRunnerWithoutCredential'` passed on 2026-06-08 after adding Copy Next Actions to diagnostics: 4 XCTest tests, 0 failures.
- Latest `swift test --filter 'ExtensionRegistryTests/writesAllExampleTemplates|ExtensionRegistryTests/exampleTemplateReadmePreservesExistingContributorNotes|ExtensionRegistryTests/extensionStarterRulesSurfaceContributionConstraints'` passed on 2026-06-08 after adding generated README checklists to extension starter folders: 3 Swift Testing tests, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoNotesUseLocalFirstAICopy` passed on 2026-06-08 after adding Copy Task, Copy Diff, and Copy Next Actions to DemoNotes onboarding: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testExtensionSettingsLinksToContributionGuide|ExtensionRegistryTests/writesAllExampleTemplates'` passed on 2026-06-08 after surfacing starter README checklists in Settings: 1 XCTest test and 1 Swift Testing test, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/extensionDashboardSummaryCountsInstalledLanesAndWarnings` passed on 2026-06-08 after adding the generated README checklist to Settings > Extensions copied summaries: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after making Settings creation status confirm generated README checklists: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testReadingTrailEmptyStateOffersWorkflowRecovery` and `swift test --filter CribbleUITests/testDemoNotesUseLocalFirstAICopy` passed on 2026-06-08 after adding Copy Trail Summary to the Reading Trail footer and DemoNotes tour: 2 focused XCTest runs, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoNotesUseLocalFirstAICopy` passed on 2026-06-08 after adding the inline Remote Runner Setup Review example to DemoNotes: 1 XCTest test, 0 failures.
- Latest `swift test --filter 'CribbleUITests/testShortcutPopoverSurfacesHelpRecoveryPaths|CribbleUITests/testWelcomeStarterChecklistGuidesCoreProductTour'` passed on 2026-06-08 after surfacing Copy Trail Summary in native first-run guidance: 2 XCTest tests, 0 failures.
- Latest `swift test --filter FolderScannerTests/testScannerSkipsHeavyGeneratedDirectories` passed on 2026-06-08 after expanding generated/tool-cache directory skips: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testHelpMenuGroupsGuidesTemplatesAndDiagnostics` passed on 2026-06-08 after adding Copy Reading Trail Summary to the native Help menu: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testReadingTrailEmptyStateOffersWorkflowRecovery` passed on 2026-06-08 after aligning Reading Trail panel copy feedback with the native command status: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after adding Copy Warnings to extension validation issues: 1 XCTest test, 0 failures.
- Latest `swift test --filter DiagnosticsCenterTests/testExtensionSnapshotFormatsInstalledLanesAndWarnings` passed on 2026-06-08 after adding the Copy Warnings route to extension diagnostics: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testDemoNotesUseLocalFirstAICopy` passed on 2026-06-08 after teaching DemoNotes the Copy Warnings validation loop: 1 XCTest test, 0 failures.
- Latest `swift test --filter ExtensionRegistryTests/writesAllExampleTemplates` passed on 2026-06-08 after adding Copy Warnings to generated extension starter READMEs: 1 Swift Testing test, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after adding status feedback for extension enable/disable toggles: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after adding status feedback for future executable trust revoke/clear actions: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testExtensionSettingsLinksToContributionGuide` passed on 2026-06-08 after adding status feedback for extension folder and manifest Reveal actions: 1 XCTest test, 0 failures.
- Latest `swift test --filter CribbleUITests/testSettingsExposeProjectIntelligenceControls` passed on 2026-06-08 after adding Copy Review to Settings > Project Intelligence: 1 XCTest test, 0 failures.
- Full `swift test` passed on 2026-06-08 after the latest Help command,
  Decision Log DemoNotes, remote-runner, diagnostics, and report work: 235
  XCTest tests and 43 Swift Testing tests, 0 failures. The run printed the
  known intermittent CoreData XPC messages from the macOS test environment, but
  all tests passed.
- Latest runs built without the previous SQLite vector-binding or MLX cache-limit warnings.

## Next best sections

1. Continue reducing warning noise from broader full-suite builds as new dependency APIs shift.
2. Keep expanding DemoNotes around real team workflows: research review, project intelligence, extension authoring, and import-lane planning.
3. Add signed bundle verification only after the consent/revocation path is fully wired into an executable plugin sandbox.

Note: a first attempt to pass FSEvent changed paths into the store hit a Swift 6.3 compiler crash in sendability analysis, so that risky path was not kept. The committed performance work stays on a stable preview-cache path.
