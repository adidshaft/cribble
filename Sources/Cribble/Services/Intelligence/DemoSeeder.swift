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
        let looksLikeDemo = fm.fileExists(atPath: rootURL.appendingPathComponent("Feature Tour.md").path)
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

    This workspace contains Markdown demonstrations showcasing Cribble's core features.

    ## Files

    | File | Purpose | Key Topics |
    |------|---------|------------|
    | Feature Tour.md | Interactive walkthrough | Wiki links, highlights, bookmarks |
    | Markdown Showcase.md | Rendering reference | LaTeX equations, Mermaid diagrams, task lists |
    | Diagnostics.md | Troubleshooting guide | Diagnostic reports, system checks |

    ## Connections

    - **Feature Tour** references concepts demonstrated in **Markdown Showcase** (e.g., wiki link syntax).
    - **Diagnostics** is standalone — no inbound or outbound wiki links.

    ## Statistics

    - 3 documents, ~2,400 words total
    - 5 wiki links across documents
    - 2 Mermaid diagrams, 1 LaTeX block
    """

    private static let contentMap = """
    # Content Map

    How the demo notes relate to each other and the features they show.

    ```mermaid
    graph LR
        FT["Feature Tour"] -->|wiki link| MS["Markdown Showcase"]
        FT -->|references| D["Diagnostics"]

        FT ---|topics| WL["Wiki Links"]
        FT ---|topics| HL["Highlights"]
        FT ---|topics| BM["Bookmarks"]

        MS ---|topics| MM["Mermaid Diagrams"]
        MS ---|topics| LX["LaTeX Math"]
        MS ---|topics| TL["Task Lists"]
    ```
    """

    private static let contentQuality = """
    # Content Quality Audit — DemoNotes

    ## Observations

    - **Diagnostics.md** has no inbound wiki links from other notes. Consider adding
      a `[[Diagnostics]]` reference in Feature Tour under a "Troubleshooting" section.
    - **Markdown Showcase.md** contains a Mermaid `pie` chart but no `sequenceDiagram`.
      The app supports both — consider adding a sequence diagram example.
    - **Feature Tour.md** mentions "bookmarks" but does not include a visible bookmark
      demonstration. A seeded bookmark annotation would make the feature self-documenting.

    ## Coverage

    | Feature | Demonstrated | Notes |
    |---------|-------------|-------|
    | Wiki links | ✅ | 5 links across 2 files |
    | Highlights | ✅ | Feature Tour includes examples |
    | Bookmarks | ⚠️ | Mentioned but not demonstrated |
    | Mermaid | ✅ | Pie chart in Showcase |
    | LaTeX | ✅ | Equations in Showcase |
    | Task lists | ✅ | Nested tasks in Showcase |
    """
}
