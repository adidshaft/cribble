import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var semanticIndex: SemanticSearchIndex
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var iconPickerTarget: FolderIconTarget?

    var body: some View {
        VStack(spacing: 0) {
            SidebarControls()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if !semanticIndex.results.isEmpty {
                SemanticResultsSection(results: semanticIndex.results) { url in
                    library.selectedURL = url
                }
            }

            if library.filteredNodes.isEmpty {
                if semanticIndex.results.isEmpty {
                    VStack {
                        Spacer()
                        ContentUnavailableView("No Markdown Files", systemImage: "doc.text.magnifyingglass")
                            .padding(.vertical, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // No literal filename matches, but semantic matches exist —
                    // let the Related section above carry the result.
                    Spacer(minLength: 0)
                }
            } else {
                List(library.filteredNodes, children: \.childNodes, selection: $library.selectedURL) { node in
                    sidebarRow(node)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Cribble")
        .onChange(of: library.selectedURL) { _, newValue in
            library.select(url: newValue)
        }
        .onChange(of: library.searchText) { _, query in
            semanticIndex.search(query: query)
        }
        .sheet(item: $iconPickerTarget) { target in
            FolderIconPicker(
                folderName: target.name,
                currentSymbol: library.folderIcon(for: target.url)
            ) { symbol in
                library.setFolderIcon(symbol, for: target.url)
            }
        }
    }

    /// Extracted from the `List` builder to keep the generic row expression
    /// within the type-checker's budget.
    @ViewBuilder
    private func sidebarRow(_ node: MarkdownNode) -> some View {
        SidebarRow(node: node)
            .tag(Optional(node.url))
            .modifier(PathfinderDragDrop(node: node) { source, target in
                library.pathfinderRequest = PathfinderRequest(source: source, target: target)
            })
            .contextMenu {
                if node.kind == .folder {
                    Button(
                        library.isPinned(node.url) ? "Unpin Folder" : "Pin Folder",
                        systemImage: library.isPinned(node.url) ? "pin.slash" : "pin"
                    ) {
                        library.togglePin(node.url)
                    }

                    Button("Choose Icon\u{2026}", systemImage: "square.grid.2x2") {
                        iconPickerTarget = FolderIconTarget(url: node.url, name: node.name)
                    }
                    if library.folderIcon(for: node.url) != nil {
                        Button("Reset Icon", systemImage: "arrow.uturn.backward") {
                            library.setFolderIcon(nil, for: node.url)
                        }
                    }
                }

                if library.isImportedRoot(node.url) {
                    Divider()

                    Button("Open Project Intelligence", systemImage: "brain") {
                        Task {
                            // Switch the engine to this project if it isn't the
                            // currently-enabled one, then show the HUD.
                            if intelligence.enabledRootPath != node.url.standardizedFileURL.path {
                                await intelligence.enable(rootURL: node.url)
                            }
                            IntelligenceHUDController.shared.show()
                        }
                    }

                    Button("Rename Folder...", systemImage: "pencil") {
                        library.renameImportedFolder(node.url)
                    }

                    Button("Copy Actual Path", systemImage: "doc.on.doc") {
                        library.copyActualPath(for: node.url)
                    }

                    Divider()

                    Button("Remove Folder", systemImage: "folder.badge.minus", role: .destructive) {
                        library.removeFolder(node.url)
                    }
                }
            }
    }
}

/// Makes a markdown row a Pathfinder drag source and drop target: drop one note
/// onto another to bridge them. Folders are left untouched.
private struct PathfinderDragDrop: ViewModifier {
    let node: MarkdownNode
    let onBridge: (URL, URL) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if node.isMarkdownFile {
            content
                .draggable(node.url) {
                    Label(node.name, systemImage: "doc.text")
                        .padding(6)
                }
                .dropDestination(for: URL.self) { items, _ in
                    guard let source = items.first?.standardizedFileURL else { return false }
                    let target = node.url.standardizedFileURL
                    guard source != target, source.pathExtension.lowercased() == "md" else { return false }
                    onBridge(source, target)
                    return true
                } isTargeted: { isTargeted = $0 }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
        } else {
            content
        }
    }
}

/// Compact "Related" section listing the top semantic matches for the current
/// query — surfaces notes that mean the same thing even when the filename
/// shares no keywords (e.g. searching "installation" → "Quick Setup").
private struct SemanticResultsSection: View {
    let results: [SemanticHit]
    let onSelect: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .semibold))
                Text("Related")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 3)

            ForEach(results) { hit in
                Button {
                    onSelect(hit.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(hit.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
            }

            Divider()
                .padding(.top, 5)
        }
        .padding(.bottom, 2)
    }
}

private struct SidebarControls: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var intelligence: IntelligenceEngine

    var body: some View {
        controls
    }

    private var controls: some View {
        HStack(spacing: 14) {
            groupedControls

            intelligenceButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupedControls: some View {
        HStack(spacing: 3) {
            sidebarIconButton(
                title: "Open Folder",
                systemImage: "folder.badge.plus",
                help: "Open a Markdown folder and keep it in the sidebar"
            ) {
                library.chooseFolder(sortMode: settings.fileSortMode)
            }

            sidebarIconButton(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                disabled: !library.hasFolders,
                help: "Reload the opened Markdown folders"
            ) {
                library.refresh(sortMode: settings.fileSortMode)
            }

            sidebarIconButton(
                title: "Remove Folder",
                systemImage: "folder.badge.minus",
                disabled: library.selectedRootURL == nil,
                help: "Remove the selected folder from Cribble without deleting files"
            ) {
                library.removeSelectedFolder()
            }

            sortMenu

            sidebarIconButton(
                title: "Tasks",
                systemImage: "checklist",
                disabled: !library.hasFolders,
                help: "Open Tasks.md — everything you've collected from your notes"
            ) {
                library.openTasksFile()
            }
        }
        .padding(4)
        .cribbleInteractiveGlass(in: Capsule())
    }

    private var intelligenceButton: some View {
        Button {
            toggleIntelligence()
        } label: {
            Label("Project Intelligence", systemImage: intelligenceSymbol)
        }
        .disabled(activeIntelligenceRoot == nil)
        .sidebarIntelligenceIcon(disabled: activeIntelligenceRoot == nil, isOn: isIntelligenceOn)
        .tint(isIntelligenceOn ? .green : .accentColor)
        .help(intelligenceHelp)
        .accessibilityValue(isIntelligenceOn ? "On" : "Off")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort Files", selection: $settings.fileSortMode) {
                ForEach(FileSortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .disabled(!library.hasFolders)
        .menuIndicator(.hidden)
        .sidebarControlIcon(disabled: !library.hasFolders)
        .help("Sort files inside folders by name, created date, or updated date")
    }

    private func sidebarIconButton(
        title: String,
        systemImage: String,
        disabled: Bool = false,
        prominent: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .disabled(disabled)
        .sidebarControlIcon(disabled: disabled, selected: prominent)
        .help(help)
    }

    private var activeIntelligenceRoot: URL? {
        library.activeRootURL?.standardizedFileURL
    }

    private var isIntelligenceOn: Bool {
        guard let activeIntelligenceRoot else { return false }
        return intelligence.isEnabled
            && !intelligence.isAllFolders
            && intelligence.enabledRootPath == activeIntelligenceRoot.path
    }

    private func toggleIntelligence() {
        guard let activeIntelligenceRoot else { return }
        Task {
            if isIntelligenceOn {
                await intelligence.disable()
            } else {
                await intelligence.enable(rootURL: activeIntelligenceRoot)
            }
        }
    }

    private var intelligenceSymbol: String {
        "brain.head.profile"
    }

    private var intelligenceHelp: String {
        guard let activeIntelligenceRoot else {
            return "Open a folder to turn Project Intelligence on"
        }
        let folderName = activeIntelligenceRoot.lastPathComponent
        if !isIntelligenceOn {
            return "Turn on Project Intelligence for \(folderName)"
        }
        return switch intelligence.status {
        case .off: "Turn on Project Intelligence for \(folderName)"
        case .ready: "Project Intelligence is on for \(folderName)"
        case .scanning: "Scanning \(folderName)"
        case .working: "Processing Project Intelligence for \(folderName)"
        case .idle: "Project Intelligence is on and up to date"
        case .driftDetected(let n): "\(n) architecture drift change(s) detected"
        }
    }
}

private extension View {
    func sidebarControlIcon(disabled: Bool = false, selected: Bool = false) -> some View {
        self
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .background {
                if selected {
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.28), radius: 7, y: 1)
                }
            }
            .buttonStyle(.plain)
            .opacity(disabled ? 0.38 : 1)
    }

    func sidebarIntelligenceIcon(disabled: Bool = false, isOn: Bool = false) -> some View {
        self
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .cribbleGlassButton(prominent: isOn)
            .opacity(disabled ? 0.38 : 1)
    }
}

struct FolderIconTarget: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

private struct SidebarRow: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    let node: MarkdownNode

    private var isPinned: Bool {
        node.kind == .folder && library.isPinned(node.url)
    }

    private var customIcon: String? {
        node.kind == .folder ? library.folderIcon(for: node.url) : nil
    }

    private var iconName: String {
        if let customIcon { return customIcon }
        return node.kind == .folder ? "folder" : "doc.text"
    }

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(node.name)
                    .lineLimit(1)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            // Custom folder icons take the accent tint so they read as a
            // deliberate choice (like a colored Finder folder); defaults stay
            // secondary to keep the sidebar calm.
            Image(systemName: iconName)
                .foregroundStyle(customIcon != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .notePreviewPopover(url: node.kind == .markdown ? node.url : nil)
    }
}
