import Foundation

/// Extracts assistant text from `claude --print --output-format stream-json
/// --include-partial-messages` output (one JSON object per line), so the HUD
/// can render tokens live instead of waiting for the whole answer.
///
/// Robust to arbitrary chunk boundaries (lines split across reads) and to
/// non-stream-json output: if the stream never parses as stream-json, the raw
/// text is treated as the answer so chat still works.
final class ClaudeCLIStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var lineBuffer = ""
    private var raw = ""
    private var sawStreamJSON = false
    private var deltas = ""
    private var assistantTexts: [String] = []
    private var result: String?

    /// Feeds decoded stdout text; returns new answer text to surface in the UI.
    func consume(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return lock.withLock {
            raw += text
            lineBuffer += text
            var emitted = ""
            while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                let line = String(lineBuffer[..<newlineIndex])
                lineBuffer.removeSubrange(...newlineIndex)
                emitted += handleLine(line)
            }
            return emitted
        }
    }

    /// Flushes a trailing line that arrived without a newline; returns any
    /// final delta it contained.
    func finish() -> String {
        lock.withLock {
            let line = lineBuffer
            lineBuffer = ""
            return handleLine(line)
        }
    }

    /// The best final answer given everything seen, in priority order: the
    /// CLI's authoritative `result` event, then accumulated streamed deltas,
    /// then complete assistant messages, then (non-stream-json fallback) the
    /// raw output.
    var answer: String {
        lock.withLock {
            if sawStreamJSON {
                if let result, !result.isEmpty { return result }
                if !deltas.isEmpty { return deltas }
                return assistantTexts.joined(separator: "\n\n")
            }
            return raw
        }
    }

    /// Must be called with `lock` held.
    private func handleLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String
        else { return "" }
        sawStreamJSON = true

        switch type {
        case "stream_event":
            // Partial-message deltas — the live token stream.
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return "" }
            deltas += text
            return text
        case "assistant":
            // Complete assistant turns (emitted even without partial messages).
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return "" }
            let texts = content.compactMap { block -> String? in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }
            if !texts.isEmpty { assistantTexts.append(texts.joined(separator: "\n\n")) }
            return ""
        case "result":
            result = object["result"] as? String
            return ""
        default:
            return ""
        }
    }
}
