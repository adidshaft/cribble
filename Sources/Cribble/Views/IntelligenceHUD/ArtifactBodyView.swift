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
    /// Called with a Mermaid source to open the full-screen zoom inspector.
    var onExpand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    StructuredText(markdown: markdown).textSelection(.enabled)
                case .mermaid(let source):
                    MermaidBlock(source: source, onOpenSource: onOpenSource, onExpand: { onExpand(source) })
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

/// One Mermaid diagram block: renders at its full natural height (no clipping)
/// and offers an expand button to open the zoom inspector — matching how the
/// reader treats diagrams.
private struct MermaidBlock: View {
    let source: String
    var onOpenSource: (String) -> Void
    var onExpand: () -> Void

    @State private var contentHeight: CGFloat = 200
    @State private var hovering = false

    var body: some View {
        MermaidDiagramWeb(source: source, contentHeight: $contentHeight, onOpenSource: onOpenSource)
            .frame(height: contentHeight)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(6)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(8)
                .opacity(hovering ? 1 : 0.4)
                .help("Expand diagram")
            }
            .onHover { hovering = $0 }
    }
}

/// A WKWebView that renders one Mermaid diagram using the bundled renderer, with
/// `securityLevel: 'loose'` so node `click` callbacks work. Clicking a file node
/// calls an in-page `cribbleOpen(path)` JS function that posts to a script-message
/// handler — kept in-page so it never reaches the system URL opener. Reports its
/// rendered height so the SwiftUI frame fits the whole diagram (no clipping).
private struct MermaidDiagramWeb: NSViewRepresentable {
    let source: String
    @Binding var contentHeight: CGFloat
    var onOpenSource: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight, onOpenSource: onOpenSource) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "cribbleOpen")
        config.userContentController.add(context.coordinator, name: "height")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(for: source), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenSource = onOpenSource
        context.coordinator.contentHeight = $contentHeight
        if context.coordinator.lastSource != source {
            context.coordinator.lastSource = source
            webView.loadHTMLString(Self.html(for: source), baseURL: nil)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cribbleOpen")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeight: Binding<CGFloat>
        var onOpenSource: (String) -> Void
        var lastSource: String?
        init(contentHeight: Binding<CGFloat>, onOpenSource: @escaping (String) -> Void) {
            self.contentHeight = contentHeight
            self.onOpenSource = onOpenSource
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "cribbleOpen":
                guard let path = message.body as? String, !path.isEmpty else { return }
                onOpenSource(path)
            case "height":
                guard let h = message.body as? NSNumber else { return }
                // Clamp: never collapse, never let a huge graph dominate inline
                // (the outer reader scrolls; expand shows it full-screen).
                contentHeight.wrappedValue = min(900, max(120, CGFloat(h.doubleValue)))
            default: break
            }
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
          const reportHeight = () => {
            try {
              const h = Math.ceil(document.getElementById('d').getBoundingClientRect().height) + 24;
              window.webkit.messageHandlers.height.postMessage(h);
            } catch (e) {}
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
            requestAnimationFrame(() => { reportHeight(); setTimeout(reportHeight, 250); });
          })();
        </script></body></html>
        """
    }
}
