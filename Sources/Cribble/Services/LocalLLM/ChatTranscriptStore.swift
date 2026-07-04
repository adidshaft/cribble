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

    /// Most recent archived conversations kept for restore; older ones age out.
    nonisolated static let maxArchivedConversations = 20

    /// A finished conversation saved when the user starts a new chat.
    struct ArchivedConversation: Codable, Identifiable {
        let id: UUID
        let savedAt: Date
        let messages: [ChatMessage]

        /// Menu label: the first question, else a fallback.
        var title: String {
            let first = messages.first(where: { $0.role == .user })?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first, !first.isEmpty else { return "Conversation" }
            return String(first.prefix(60))
        }
    }

    private let fileURL: URL
    private let historyURL: URL

    init(fileURL: URL = ChatTranscriptStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.historyURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("ChatHistory.json")
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

    // MARK: - Conversation history

    /// Moves the current conversation (if any) into the bounded history, then
    /// clears the live transcript. Called when the user starts a new chat, so
    /// New Chat parks the conversation instead of destroying it.
    func archiveCurrentAndClear() {
        let current = load()
        defer { clear() }
        guard current.contains(where: { $0.role == .user }) else { return }
        var history = recentConversations()
        history.insert(ArchivedConversation(id: UUID(), savedAt: Date(), messages: current), at: 0)
        writeHistory(Array(history.prefix(Self.maxArchivedConversations)))
    }

    /// Newest-first archived conversations.
    func recentConversations() -> [ArchivedConversation] {
        guard let data = try? Data(contentsOf: historyURL),
              let payload = try? JSONDecoder().decode(HistoryPayload.self, from: data)
        else { return [] }
        return payload.conversations
    }

    /// Removes one conversation from the history (used after it's restored so
    /// re-archiving can't duplicate it).
    func removeFromHistory(id: UUID) {
        let remaining = recentConversations().filter { $0.id != id }
        writeHistory(remaining)
    }

    private func writeHistory(_ conversations: [ArchivedConversation]) {
        do {
            if conversations.isEmpty {
                try? FileManager.default.removeItem(at: historyURL)
                return
            }
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(HistoryPayload(conversations: conversations))
            try data.write(to: historyURL, options: [.atomic])
        } catch {
            DiagnosticsCenter.shared.record(
                level: .error,
                message: "Failed to save chat history: \(error.localizedDescription)"
            )
        }
    }

    private struct Payload: Codable {
        var messages: [ChatMessage]
    }

    private struct HistoryPayload: Codable {
        var conversations: [ArchivedConversation]
    }

    nonisolated private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
            .appendingPathComponent("ChatTranscript.json")
    }
}
