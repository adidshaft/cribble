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
/// `securityLevel: 'loose'` so node `click` callbacks work. Clicking a file node
/// calls an in-page `cribbleOpen(path)` JS function that posts to a script-message
/// handler — kept in-page so it never reaches the system URL opener. Degrades
/// gracefully: if anything fails, the diagram simply isn't interactive.
private struct MermaidDiagramWeb: NSViewRepresentable {
    let source: String
    var onOpenSource: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenSource: onOpenSource) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "cribbleOpen")
        let webView = WKWebView(frame: .zero, configuration: config)
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

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cribbleOpen")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onOpenSource: (String) -> Void
        var lastSource: String?
        init(onOpenSource: @escaping (String) -> Void) { self.onOpenSource = onOpenSource }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "cribbleOpen", let path = message.body as? String, !path.isEmpty else { return }
            onOpenSource(path)
        }

        // Safety net: never let the diagram navigate the web view anywhere (no
        // external URLs, no custom schemes hitting the system opener).
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            decisionHandler((url == nil || url?.absoluteString == "about:blank") ? .allow : .cancel)
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
          .node{cursor:pointer;}
        </style></head>
        <body><div id="d"></div>
        <script>
          window.cribbleOpen = function(p) {
            try { window.webkit.messageHandlers.cribbleOpen.postMessage(String(p)); } catch (e) {}
          };
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
