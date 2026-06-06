import AppKit
import SwiftUI
import WebKit

struct GraphPayload: Codable, Equatable {
    var title: String
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var isPlaceholder: Bool = false

    static var empty: GraphPayload {
        GraphPayload(title: "Graph", nodes: [], edges: [], isPlaceholder: true)
    }
}

struct GraphNode: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var kind: String
    var path: String?
    var weight: Int = 1
}

struct GraphEdge: Codable, Identifiable, Equatable {
    var id: String
    var source: String
    var target: String
    var label: String?
    var kind: String
    var status: String = "accepted"
    var origin: String = "deterministic"
}

@MainActor
struct GraphViewport: NSViewRepresentable {
    let payload: GraphPayload
    var onOpenSource: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenSource: onOpenSource)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "openSource")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(for: payload), baseURL: nil)
        context.coordinator.lastPayload = payload
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenSource = onOpenSource
        guard context.coordinator.lastPayload != payload else { return }
        context.coordinator.lastPayload = payload
        webView.loadHTMLString(Self.html(for: payload), baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openSource")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onOpenSource: (String) -> Void
        var lastPayload: GraphPayload?

        init(onOpenSource: @escaping (String) -> Void) {
            self.onOpenSource = onOpenSource
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "openSource",
                  let path = message.body as? String,
                  !path.isEmpty
            else { return }
            onOpenSource(path)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler((url == nil || url?.absoluteString == "about:blank") ? .allow : .cancel)
        }
    }

    private static func html(for payload: GraphPayload) -> String {
        let encodedPayload = (try? String(data: JSONEncoder().encode(payload), encoding: .utf8)) ?? "{}"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script>\(GraphResource.script())</script>
          <style>
            html, body, #graph {
              width: 100%;
              height: 100%;
              margin: 0;
              padding: 0;
              overflow: hidden;
              background: transparent;
              color: #f2f2f2;
              font: 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            #empty, #error {
              box-sizing: border-box;
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 24px;
              color: rgba(242, 242, 242, 0.58);
              text-align: center;
              line-height: 1.45;
            }
            #error {
              color: #e5b4b4;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              white-space: pre-wrap;
            }
          </style>
        </head>
        <body>
          <div id="graph"></div>
          <script>
            const payload = \(encodedPayload);
            const root = document.getElementById('graph');
            let cy = null;

            const postOpen = path => {
              try { window.webkit.messageHandlers.openSource.postMessage(String(path)); } catch (e) {}
            };

            const colorFor = kind => ({
              project: '#8ab4f8',
              folder: '#f6c453',
              artifact: '#d7aefb',
              file: '#81c995',
              note: '#7dd3fc',
              module: '#f28b82',
              topic: '#c8c8c8'
            })[kind] || '#c8c8c8';

            const escapeHTML = value => String(value).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

            function renderGraph(nextPayload) {
              if (!globalThis.cytoscape) {
                root.innerHTML = '<div id="error">Bundled Cytoscape renderer did not load.</div>';
                return;
              }
              if (!nextPayload || !Array.isArray(nextPayload.nodes) || nextPayload.nodes.length === 0) {
                root.innerHTML = '<div id="empty">Graph data will appear here after intelligence builds relationships.</div>';
                return;
              }
              root.innerHTML = '';
              if (cy) cy.destroy();

              const nodes = nextPayload.nodes.map(node => ({
                data: {
                  id: String(node.id),
                  label: String(node.label || node.id),
                  kind: String(node.kind || 'topic'),
                  path: node.path || '',
                  color: colorFor(String(node.kind || 'topic')),
                  weight: Math.max(1, Number(node.weight || 1))
                }
              }));
              const edges = (nextPayload.edges || []).map((edge, index) => ({
                data: {
                  id: edge.id || `e${index}`,
                  source: String(edge.source),
                  target: String(edge.target),
                  label: edge.label || '',
                  kind: edge.kind || 'relationship',
                  status: edge.status || 'accepted',
                  origin: edge.origin || 'deterministic'
                }
              }));

              cy = cytoscape({
                container: root,
                elements: nodes.concat(edges),
                minZoom: 0.3,
                maxZoom: 2.4,
                wheelSensitivity: 0.22,
                style: [
                  {
                    selector: 'node',
                    style: {
                      'background-color': 'data(color)',
                      'border-color': 'rgba(255,255,255,0.72)',
                      'border-width': 1,
                      'color': '#f3f3f3',
                      'font-family': '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                      'font-size': 10,
                      'height': 'mapData(weight, 1, 8, 22, 42)',
                      'label': 'data(label)',
                      'overlay-opacity': 0,
                      'text-background-color': 'rgba(0,0,0,0.42)',
                      'text-background-opacity': 1,
                      'text-background-padding': 3,
                      'text-margin-y': -8,
                      'text-max-width': 92,
                      'text-outline-color': 'rgba(0,0,0,0.32)',
                      'text-outline-width': 1,
                      'text-wrap': 'wrap',
                      'width': 'mapData(weight, 1, 8, 22, 42)'
                    }
                  },
                  {
                    selector: 'edge',
                    style: {
                      'curve-style': 'bezier',
                      'line-color': 'rgba(220,220,220,0.42)',
                      'target-arrow-color': 'rgba(220,220,220,0.48)',
                      'target-arrow-shape': 'triangle',
                      'width': 1.2,
                      'label': 'data(label)',
                      'font-size': 8,
                      'color': 'rgba(242,242,242,0.52)',
                      'text-background-color': 'rgba(0,0,0,0.34)',
                      'text-background-opacity': 1,
                      'text-background-padding': 2
                    }
                  },
                  {
                    selector: 'edge[status = "suggested"]',
                    style: {
                      'line-style': 'dashed',
                      'line-color': 'rgba(125, 211, 252, 0.52)',
                      'target-arrow-color': 'rgba(125, 211, 252, 0.62)'
                    }
                  },
                  {
                    selector: 'node:selected',
                    style: {
                      'border-color': '#ffffff',
                      'border-width': 2
                    }
                  }
                ],
                layout: {
                  name: nodes.length > 5 ? 'cose' : 'circle',
                  animate: false,
                  fit: true,
                  padding: 36,
                  nodeRepulsion: 7000,
                  idealEdgeLength: 96,
                  edgeElasticity: 0.18
                }
              });

              cy.on('tap', 'node', event => {
                const path = event.target.data('path');
                if (path) postOpen(path);
              });
              cy.on('mouseover', 'node', event => {
                root.style.cursor = event.target.data('path') ? 'pointer' : 'default';
              });
              cy.on('mouseout', 'node', () => { root.style.cursor = 'default'; });
              setTimeout(() => cy && cy.fit(undefined, 36), 150);
            }

            window.addEventListener('resize', () => { if (cy) cy.fit(undefined, 36); });

            try {
              renderGraph(payload);
            } catch (error) {
              root.innerHTML = '<div id="error">' + escapeHTML(error && error.message || error) + '</div>';
            }
          </script>
        </body>
        </html>
        """
    }
}

@MainActor
private enum GraphResource {
    static func script() -> String {
        guard let url = MarkdownLibraryStore.bundledResourceURL(forResource: "cytoscape.min", withExtension: "js", subdirectory: "Graph")
                ?? MarkdownLibraryStore.bundledResourceURL(forResource: "cytoscape.min", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "window.__cribbleCytoscapeMissing = true;"
        }
        return script.replacingOccurrences(of: "</script", with: "<\\/script")
    }
}
