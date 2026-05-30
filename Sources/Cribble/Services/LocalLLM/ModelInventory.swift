import Foundation

/// Whether a catalog entry is ready to use right now.
enum ModelAvailability {
    /// Cloud provider — nothing to download.
    case cloud
    /// On-device model already present in the Hugging Face cache.
    case downloaded
    /// On-device model that will download on first use.
    case notDownloaded
}

/// Checks whether an on-device model has already been downloaded, by looking in
/// the standard Hugging Face hub cache (shared with the Python tooling). Used to
/// drive the download-state icons in the model picker.
enum ModelInventory {
    static func availability(of model: LocalModel) -> ModelAvailability {
        if model.kind.isCloud { return .cloud }
        return isDownloaded(model) ? .downloaded : .notDownloaded
    }

    static func isDownloaded(_ model: LocalModel) -> Bool {
        guard model.kind == .localMLX else { return false }
        // HF hub layout: <cache>/hub/models--<org>--<name>/snapshots/<rev>/…
        let folder = "models--" + model.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        for hub in hubDirectories() {
            if hasWeights(in: hub.appendingPathComponent(folder)) {
                return true
            }
        }
        return false
    }

    private static func hubDirectories() -> [URL] {
        var bases: [URL] = []
        let env = ProcessInfo.processInfo.environment
        if let cache = env["HF_HUB_CACHE"], !cache.isEmpty {
            bases.append(URL(fileURLWithPath: cache))
        }
        if let home = env["HF_HOME"], !home.isEmpty {
            bases.append(URL(fileURLWithPath: home).appendingPathComponent("hub"))
        }
        // Non-sandboxed macOS: ~/.cache/huggingface/hub
        bases.append(URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/huggingface/hub"))
        // Sandboxed apps: Library/Caches/huggingface/hub
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            bases.append(caches.appendingPathComponent("huggingface/hub"))
        }
        return bases
    }

    private static func hasWeights(in repoDir: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: repoDir.path) else { return false }
        let snapshots = repoDir.appendingPathComponent("snapshots")
        guard let enumerator = fm.enumerator(at: snapshots, includingPropertiesForKeys: nil) else {
            return false
        }
        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            return true
        }
        return false
    }
}
