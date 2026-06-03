# Intelligence

Background workspace intelligence: Cribble quietly analyzes an opened library to
build connection graphs, dependency maps, and searchable vectors that power the
Intelligence HUD and richer AI answers. All work is local and incremental.

See the [intelligence plan](../../../../docs/cribble-intelligence-plan.md) and
[research notes](../../../../docs/cribble-intelligence-research.md) for design.

## Orchestration

| File | Responsibility |
| --- | --- |
| `IntelligenceEngine.swift` | Top-level coordinator for analysis runs. |
| `BackgroundScheduler.swift` | Schedules incremental jobs off the main thread. |
| `JobRunner.swift` | Executes and tracks individual analysis jobs. |
| `IntelligenceDatabase.swift` | Persistent store for derived artifacts. |
| `ContentHasher.swift` | Change detection so only edited notes re-run. |

## Analyzers

| File | Responsibility |
| --- | --- |
| `WorkspaceScanner.swift` | Discovers files/structure to analyze. |
| `NoteConnectionsGraph.swift` | Builds the note-to-note link graph. |
| `DependencyGraph.swift` | Models dependencies between artifacts. |
| `SwiftSymbolExtractor.swift` | Extracts symbols from Swift code notes. |
| `GitInspector.swift` | Reads Git metadata for a workspace. |
| `VectorIndex.swift` | Embedding vectors for semantic features. |

## Providers, artifacts & safety

| File | Responsibility |
| --- | --- |
| `IntelligenceProvider.swift` / `OpenAICompatibleProvider.swift` | Pluggable model providers. |
| `Prompts.swift` | Prompt templates for analysis tasks. |
| `ArtifactStore.swift` | Stores generated artifacts (summaries, diagrams). |
| `OutputValidator.swift` | Validates model output before persisting. |
| `MermaidRenderValidator.swift` | Verifies generated Mermaid actually renders. |
| `DemoSeeder.swift` | Seeds demo intelligence data for the sample library. |
| `IntelligenceModels.swift` / `IntelligenceSettings.swift` | Types + user settings. |

> Generated content is validated before storage, and never overwrites a user's
> source files — it lives alongside in the intelligence database.
