import Foundation

@MainActor
final class FileChangeMonitor: @unchecked Sendable {
    private var timer: Timer?
    private var lastSignature: String?

    func start(rootURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        start(rootURLs: [rootURL], onChange: onChange)
    }

    func start(rootURLs: [URL], onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        let roots = rootURLs
        lastSignature = signature(for: roots)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, roots] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = self.signature(for: roots)
                if current != self.lastSignature {
                    self.lastSignature = current
                    onChange()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func signature(for rootURLs: [URL]) -> String {
        rootURLs.flatMap { rootURL -> [String] in
            signatureParts(for: rootURL)
        }
        .sorted()
        .joined(separator: "|")
    }

    private func signatureParts(for rootURL: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var parts: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            parts.append("\(url.path):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return parts
    }
}
