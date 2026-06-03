import AppKit
import SwiftUI
import Textual
import WebKit

/// Renders an artifact's Markdown, but swaps any ```mermaid fences for an actual
/// rendered (and, for dependency maps, clickable) diagram instead of showing the
/// raw source. Non-diagram prose still renders via `StructuredText`.
struct ArtifactBodyView: View {
    let content: String
    /// Called with a project-relative path when a diagram node is clicked.
    var onOpenSource: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    StructuredText(markdown: markdown).textSelection(.enabled)
                case .mermaid(let source):
                    MermaidDiagramWeb(source: source, onOpenSource: onOpenSource)
                        .frame(minHeight: 240)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private enum Segment { case text(String), mermaid(String) }

    /// Splits the content into prose and mermaid blocks.
    private var segments: [Segment] {
        var result: [Segment] = []
        var textLines: [String] = []
        var mermaidLines: [String] = []
        var inMermaid = false

        func flushText() {
            let joined = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(.text(joined)) }
            textLines = []
        }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inMermaid, trimmed.hasPrefix("```mermaid") {
                flushText(); inMermaid = true; mermaidLines = []
            } else if inMermaid, trimmed == "```" {
                inMermaid = false
                result.append(.mermaid(mermaidLines.joined(separator: "\n")))
            } else if inMermaid {
                mermaidLines.append(line)
            } else {
                textLines.append(line)
            }
        }
        if inMermaid, !mermaidLines.isEmpty { result.append(.mermaid(mermaidLines.joined(separator: "\n"))) }
        flushText()
        return result
    }
}

/// A WKWebView that renders one Mermaid diagram using the bundled renderer, with
/// `securityLevel: 'loose'` so `click` links work. Node links use a `cribble://`
/// scheme intercepted here and forwarded to `onOpenSource` — the diagram becomes a
/// navigable map of the codebase (design plan §13 Phase 2). Degrades gracefully:
/// if anything fails, the diagram simply isn't interactive.
private struct MermaidDiagramWeb: NSViewRepresentable {
    let source: String
    var onOpenSource: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenSource: onOpenSource) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(for: source), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenSource = onOpenSource
        if context.coordinator.lastSource != source {
            context.coordinator.lastSource = source
            webView.loadHTMLString(Self.html(for: source), baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onOpenSource: (String) -> Void
        var lastSource: String?
        init(onOpenSource: @escaping (String) -> Void) { self.onOpenSource = onOpenSource }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            if url.scheme == "cribble" {
                // cribble://open/<percent-encoded relative path>
                let encoded = url.absoluteString
                    .replacingOccurrences(of: "cribble://open/", with: "")
                if let path = encoded.removingPercentEncoding, !path.isEmpty {
                    onOpenSource(path)
                }
                return decisionHandler(.cancel)
            }
            // Only allow the initial about:blank / data load; block external nav.
            decisionHandler(url.scheme == nil || url.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }

    private static func html(for source: String) -> String {
        let encoded = (try? String(data: JSONEncoder().encode(source), encoding: .utf8)) ?? "\"\""
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <script>\(MermaidHTML.script())</script>
        <style>
          html,body{margin:0;padding:0;background:transparent;color:#e8e8e8;
            font:13px -apple-system,BlinkMacSystemFont,sans-serif;}
          #d{padding:12px;display:flex;justify-content:center;}
          svg{max-width:100%;height:auto!important;}
          .err{font:12px ui-monospace,Menlo,monospace;color:#c79b9b;padding:12px;white-space:pre-wrap;}
          a{cursor:pointer;}
        </style></head>
        <body><div id="d"></div>
        <script>
          (async () => {
            const src = \(encoded);
            const root = document.getElementById('d');
            try {
              if (!globalThis.mermaid) throw new Error('Mermaid renderer unavailable.');
              mermaid.initialize({ startOnLoad: false, securityLevel: 'loose', theme: 'dark' });
              const { svg, bindFunctions } = await mermaid.render('g', src);
              root.innerHTML = svg;
              if (bindFunctions) bindFunctions(root);
            } catch (e) {
              root.innerHTML = '<pre class="err">' + String(e && e.message || e) + '</pre>';
            }
          })();
        </script></body></html>
        """
    }
}
