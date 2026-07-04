import Foundation

/// Persists the Local Chat HUD's conversation across panel closes and app
/// restarts, so a chat is never silently lost. One JSON file in Application
/// Support, written atomically; the transcript is bounded to the most recent
/// turns so the file can't grow without limit.
@MainActor
final class ChatTranscriptStore {
    /// Oldest turns beyond this are dropped on save. Generous enough for any
    /// real conversation while keeping load/save instant.
    nonisolated static let maxPersistedMessages = 200

    private let fileURL: URL

    init(fileURL: URL = ChatTranscriptStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// Loads the saved transcript. A turn that was mid-stream when the app
    /// quit is settled on restore so the HUD never comes back "generating".
    func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return [] }
        return payload.messages.map { message in
            var settled = message
            settled.isStreaming = false
            return settled
        }
    }

    /// Saves the conversation, dropping in-flight placeholders and bounding
    /// length. An empty conversation removes the file entirely.
    func save(_ messages: [ChatMessage]) {
        let settled = messages.filter { !($0.isStreaming && $0.text.isEmpty) }
        guard !settled.isEmpty else { return clear() }
        let bounded = Array(settled.suffix(Self.maxPersistedMessages))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Payload(messages: bounded))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            DiagnosticsCenter.shared.record(
                level: .error,
                message: "Failed to save chat transcript: \(error.localizedDescription)"
            )
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        var messages: [ChatMessage]
    }

    nonisolated private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
            .appendingPathComponent("ChatTranscript.json")
    }
}
