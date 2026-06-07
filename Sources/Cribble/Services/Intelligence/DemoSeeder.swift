import Foundation

/// Seeds pre-written intelligence artifacts for the bundled **DemoNotes**
/// workspace (design plan §18), so the feature demonstrates itself immediately —
/// before the user's first real intelligence run and without invoking a model.
/// Real generated artifacts later overwrite these in place (same relative paths).
enum DemoSeeder {

    /// Detects the DemoNotes workspace and, if it has no artifacts yet, seeds the
    /// example set. Returns true if it seeded.
    @discardableResult
    static func seedIfDemoNotes(
        rootURL: URL,
        store: ArtifactStore,
        db: IntelligenceDatabase,
        projectID: String
    ) async -> Bool {
        let fm = FileManager.default
        let looksLikeDemo = fm.fileExists(atPath: rootURL.appendingPathComponent("README.md").path)
            && fm.fileExists(atPath: rootURL.appendingPathComponent("Getting Started.md").path)
            && fm.fileExists(atPath: rootURL.appendingPathComponent("Feature Tour.md").path)
            && fm.fileExists(atPath: rootURL.appendingPathComponent("Markdown Showcase.md").path)
        guard looksLikeDemo else { return false }
        guard await db.artifacts(projectID: projectID).isEmpty else { return false }

        _ = try? await store.store(
            type: .projectIndex, relativePath: "project-index.md",
            title: "DemoNotes — Project Index", content: projectIndex, sourceHashes: ["seed"]
        )
        _ = try? await store.store(
            type: .architectureDiagram, relativePath: "architecture/content-map.md",
            title: "Content Map", content: contentMap, sourceHashes: ["seed"]
        )
        _ = try? await store.store(
            type: .fallbackAudit, relativePath: "audits/content-quality.md",
            title: "Content Quality Audit", content: contentQuality, sourceHashes: ["seed"]
        )
        return true
    }

    private static let projectIndex = """
    # DemoNotes — Project Index

    This workspace is a living onboarding tour for Cribble: native reading, private AI,
    tasks, Project Intelligence, research review, and the new extension framework.

    ## Files

    | File | Purpose | Key Topics |
    |------|---------|------------|
    | README.md | Tour index | Start path, checklist, role-oriented routes |
    | Getting Started.md | First reading workflow | Highlights, bookmarks, wiki links, search |
    | Cribble AI.md | Private assistant guide | Chat HUD, current-note context, patch preview |
    | Feature Tour.md | Interactive walkthrough | Zoom overlays, trails, pathfinder, semantic search |
    | Tasks and Intelligence.md | Action and analysis workflow | Tasks.md, Reminders, Calendar, Project Intelligence |
    | Workflow Playbook.md | Practical weekly flows | Reading, research, teams, remote runners |
    | Research Review.md | Evidence-heavy review | Claims, source trails, review quick actions |
    | Team Extension Kit.md | Team plugin conventions | Manifest layout, review checklist, remote-runner policy |
    | Extensions and Remote Intelligence.md | Extension and VPS path | Declarative plugins, trusted runners, importer/renderer lanes |
    | Markdown Showcase.md | Rendering reference | LaTeX equations, Mermaid diagrams, task lists |

    ## Connections

    - **README** routes beginners into **Getting Started** and power users into
      **Workflow Playbook**, **Research Review**, and **Team Extension Kit**.
    - **Tasks and Intelligence** bridges everyday checkboxes into Project Intelligence.
    - **Extensions and Remote Intelligence** and **Team Extension Kit** form the plugin
      path: safe manifests first, trusted remote runners when teams need more compute.
    - **Markdown Showcase** remains the rendering reference that other notes point to.

    ## Statistics

    - 10 tour documents covering beginner, research, team, and power-user paths
    - Extension lanes: quick actions, intelligence providers, renderers, and importers
    - Remote runner guidance includes endpoint ownership, native approval, Keychain secrets, and revocation
    """

    private static let contentMap = """
    # Content Map

    How the demo notes relate to each other and the features they show.

    ```mermaid
    graph LR
        Home["README"] --> GS["Getting Started"]
        Home --> AI["Cribble AI"]
        Home --> FT["Feature Tour"]
        Home --> TI["Tasks and Intelligence"]
        Home --> WP["Workflow Playbook"]
        Home --> RR["Research Review"]
        Home --> TEK["Team Extension Kit"]
        Home --> ERI["Extensions and Remote Intelligence"]
        Home --> MS["Markdown Showcase"]

        GS ---|reader basics| Read["Highlights / Bookmarks / Search"]
        FT ---|advanced reading| Trail["Zoom / Trails / Pathfinder"]
        AI ---|assistant| Chat["Chat HUD / Diff Preview"]
        TI ---|action loop| Tasks["Tasks.md / Reminders / Calendar"]
        TI ---|analysis| Intel["Project Intelligence"]
        RR ---|evidence| Claims["Claims / Sources / Follow-up"]
        WP ---|workflow| Teams["Readers / Researchers / Teams"]
        TEK ---|plugins| Manifests["Declarative Manifests"]
        ERI ---|runners| VPS["Trusted VPS / OpenAI-Compatible Runner"]
        MS ---|rendering| Render["Mermaid / LaTeX / Tables"]
    ```
    """

    private static let contentQuality = """
    # Content Quality Audit — DemoNotes

    ## Observations

    - The tour now covers both light and complex users: **Getting Started** for a
      two-minute path, **Workflow Playbook** for recurring work, and **Research Review**
      for evidence-heavy folders.
    - Extension onboarding has two layers: **Team Extension Kit** for team policy and
      **Extensions and Remote Intelligence** for copy-ready manifests and trusted runners.
    - **Tasks and Intelligence** connects everyday checkbox capture to broader folder
      analysis, making Project Intelligence feel useful beyond code repositories.
    - **Markdown Showcase** is intentionally retained as the renderer reference.

    ## Coverage

    | Feature | Demonstrated | Notes |
    |---------|-------------|-------|
    | Reader basics | ✅ | Getting Started and Feature Tour |
    | Private AI chat | ✅ | Cribble AI plus Chat HUD checklist |
    | Tasks workflow | ✅ | Tasks and Intelligence |
    | Project Intelligence | ✅ | Preflight, Ask, artifacts, and source trails |
    | Research review | ✅ | Claims, evidence, and follow-up actions |
    | Extension framework | ✅ | Team Extension Kit and Extensions and Remote Intelligence |
    | Remote runner trust | ✅ | Approval sheet, handoff checklist, Keychain guidance, revocation |
    | Markdown rendering | ✅ | Markdown Showcase |
    """
}
