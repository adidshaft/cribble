import AppKit
import SwiftUI
import Textual
import WebKit

// MARK: - Zoom request model

/// A request to open the full-screen zoom/pan inspector for a rendered block.
/// Diagrams and display equations both render in-line at reading width, where
/// complex content can feel cramped; this drives a Quick Look-style overlay so
/// the user can inspect them without disturbing the document flow.
struct ZoomOverlayRequest: Identifiable, Equatable {
    enum Content: Equatable {
        case mermaid(source: String)
        case math(markdown: String)
    }

    let id = UUID()
    let title: String
    let content: Content
}

// MARK: - Environment plumbing

private struct PresentZoomOverlayKey: EnvironmentKey {
    static let defaultValue: @MainActor (ZoomOverlayRequest) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Injected by the reader so any nested block (a Mermaid diagram, a display
    /// equation) can ask for the shared zoom overlay without owning it.
    var presentZoomOverlay: @MainActor (ZoomOverlayRequest) -> Void {
        get { self[PresentZoomOverlayKey.self] }
        set { self[PresentZoomOverlayKey.self] = newValue }
    }
}

// MARK: - Hover affordance

/// Reveals a subtle "scale" button on hover and (optionally) opens the zoom
/// overlay on double-click. Double-click is suppressed for text-bearing blocks
/// like display math, where it would fight the system word-selection gesture.
private struct ZoomAffordanceModifier: ViewModifier {
    let allowsDoubleClick: Bool
    let makeRequest: () -> ZoomOverlayRequest

    @Environment(\.presentZoomOverlay) private var presentZoomOverlay
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            // The inline Mermaid web view disables its own hit-testing so the
            // page scrolls; this restores a hover/tap target across the block.
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                Button {
                    presentZoomOverlay(makeRequest())
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .help("Zoom to inspect")
                .padding(10)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
            }
            .modifier(DoubleClickToZoom(enabled: allowsDoubleClick) {
                presentZoomOverlay(makeRequest())
            })
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.14), value: isHovering)
    }
}

private struct DoubleClickToZoom: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            // High-priority so the gesture wins over the web view area without
            // capturing single-clicks/scrolls used elsewhere in the reader.
            content.highPriorityGesture(
                TapGesture(count: 2).onEnded(action)
            )
        } else {
            content
        }
    }
}

extension View {
    /// Adds the hover scale button (and optional double-click) that opens the
    /// shared zoom overlay for this block.
    func zoomAffordance(
        allowsDoubleClick: Bool = false,
        _ makeRequest: @escaping () -> ZoomOverlayRequest
    ) -> some View {
        modifier(ZoomAffordanceModifier(allowsDoubleClick: allowsDoubleClick, makeRequest: makeRequest))
    }

    /// Adds the hover scale button for a pure display-equation block. No-op when
    /// `markdown` is nil (i.e. the block is not a standalone equation), so we
    /// never decorate ordinary paragraphs that merely contain inline math.
    /// Double-click is intentionally omitted: it would collide with the system
    /// word-selection gesture on the equation's text.
    @ViewBuilder
    func mathZoomAffordance(_ markdown: String?) -> some View {
        if let markdown {
            zoomAffordance { ZoomOverlayRequest(title: "Equation", content: .math(markdown: markdown)) }
        } else {
            self
        }
    }
}

// MARK: - The overlay

/// A glassmorphic, dismissible inspector panel. Click the backdrop, press
/// Escape, or hit the close control to dismiss.
struct DiagramZoomOverlay: View {
    let request: ZoomOverlayRequest
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var mermaidZoom = MermaidZoomController()
    @State private var mathScale: CGFloat = 1.6
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                Divider().opacity(0.35)
                contentArea
            }
            .frame(maxWidth: 1000, maxHeight: 760)
            .cribbleGlass(in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.30), radius: 40, y: 18)
            .padding(48)
            .scaleEffect(appeared ? 1 : 0.97)
            .opacity(appeared ? 1 : 0)
        }
        // Escape is handled by ReaderShortcutHub (a custom `.overlay` isn't in
        // the responder chain, so `.onExitCommand` here is unreliable). Kept as
        // a harmless fallback for contexts where it does fire.
        .onExitCommand(perform: onClose)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var backdrop: some View {
        Rectangle()
            .fill(.black.opacity(0.28))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .opacity(appeared ? 1 : 0)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(request.title)
                .font(.system(size: 14, design: .rounded))
                .fontWeight(.semibold)

            Spacer(minLength: 12)

            zoomControls

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                adjustZoom(by: 1 / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button(action: resetZoom) {
                Image(systemName: "1.magnifyingglass")
            }
            .help("Reset zoom")

            Button {
                adjustZoom(by: 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var contentArea: some View {
        switch request.content {
        case .mermaid(let source):
            ZoomableMermaidWebView(
                source: source,
                isDark: colorScheme == .dark,
                controller: mermaidZoom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .math(let markdown):
            ScrollView([.horizontal, .vertical]) {
                StructuredText(
                    markdown,
                    parser: HighlightedMarkdownParser(baseURL: URL(fileURLWithPath: "/"), highlights: [])
                )
                .font(.system(size: 17 * mathScale))
                .textual.structuredTextStyle(.gitHub)
                .textual.textSelection(.enabled)
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iconName: String {
        switch request.content {
        case .mermaid: "point.3.connected.trianglepath.dotted"
        case .math: "function"
        }
    }

    private func adjustZoom(by factor: CGFloat) {
        switch request.content {
        case .mermaid:
            mermaidZoom.zoom(by: factor)
        case .math:
            mathScale = min(4, max(0.6, mathScale * factor))
        }
    }

    private func resetZoom() {
        switch request.content {
        case .mermaid:
            mermaidZoom.reset()
        case .math:
            mathScale = 1.6
        }
    }
}

// MARK: - Interactive (zoomable / pannable) Mermaid web view

@MainActor
final class MermaidZoomController: ObservableObject {
    weak var webView: WKWebView?
    private var magnification: CGFloat = 1

    func zoom(by factor: CGFloat) {
        set(min(6, max(0.3, magnification * factor)))
    }

    func reset() {
        set(1)
    }

    private func set(_ value: CGFloat) {
        magnification = value
        webView?.magnification = value
    }
}

private struct ZoomableMermaidWebView: NSViewRepresentable {
    let source: String
    let isDark: Bool
    let controller: MermaidZoomController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = NonFocusableMermaidWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        webView.loadHTMLString(MermaidHTML.page(source: source, fontScale: 1.0, isDark: isDark, interactive: true), baseURL: nil)
        controller.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
    }

    /// Pinch-zoom and scroll-to-pan are gesture/scroll-wheel driven and don't
    /// need first-responder status — so we refuse it. Otherwise the web content
    /// swallows the Escape key and the overlay can't be dismissed with it.
    final class NonFocusableMermaidWebView: WKWebView {
        override var acceptsFirstResponder: Bool { false }
    }
}

// MARK: - Shared Mermaid HTML

/// Single source of truth for the Mermaid render page, shared by the in-line
/// (`MermaidWebDiagramView`) and the zoom overlay (`ZoomableMermaidWebView`).
/// `interactive` flips the page from a height-reporting, non-scrolling inline
/// render to a naturally-sized, scrollable/zoomable inspector render.
@MainActor
enum MermaidHTML {
    static func script() -> String {
        guard let url = MarkdownLibraryStore.bundledResourceURL(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid")
                ?? MarkdownLibraryStore.bundledResourceURL(forResource: "mermaid.min", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "window.__cribbleMermaidMissing = true;"
        }
        return script.replacingOccurrences(of: "</script", with: "<\\/script")
    }

    static func page(source: String, fontScale: Double, isDark: Bool, interactive: Bool) -> String {
        let encodedSource = (try? String(data: JSONEncoder().encode(source), encoding: .utf8)) ?? "\"\""
        let background = isDark ? "#151515" : "#ffffff"
        let foreground = isDark ? "#f2f2f2" : "#202124"
        let secondary = isDark ? "#a7a7a7" : "#5f6368"
        let line = isDark ? "#8ab4f8" : "#1a73e8"
        let nodeFill = isDark ? "#19324a" : "#e8f0fe"
        let nodeBorder = isDark ? "#2f6ea6" : "#1a73e8"

        let bodyOverflow = interactive ? "auto" : "hidden"
        let diagramMinHeight = interactive ? "100%" : "180px"
        let diagramAlign = interactive ? "flex-start" : "center"
        let svgMaxWidth = interactive ? "none" : "100%"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script>\(script())</script>
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: \(foreground);
              font: \(max(12, 13 * fontScale))px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              overflow: \(bodyOverflow);
            }
            #diagram {
              box-sizing: border-box;
              width: 100%;
              min-height: \(diagramMinHeight);
              padding: \(interactive ? "24px" : "10px");
              display: flex;
              align-items: center;
              justify-content: \(diagramAlign);
            }
            svg {
              max-width: \(svgMaxWidth);
              height: auto !important;
            }
            .error {
              white-space: pre-wrap;
              font: \(max(12, 13 * fontScale))px ui-monospace, SFMono-Regular, Menlo, monospace;
              color: \(secondary);
              text-align: left;
              width: 100%;
            }
          </style>
        </head>
        <body>
          <div id="diagram"></div>
          <script>
            const source = \(encodedSource);
            const root = document.getElementById('diagram');
            const reportHeight = () => {
              const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.height;
              if (!handler) return;
              const rect = document.documentElement.getBoundingClientRect();
              handler.postMessage(Math.ceil(rect.height));
            };
            const escapeHTML = value => String(value).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
            const showError = error => {
              root.innerHTML = '<pre class="error">' + escapeHTML(error) + '</pre>';
              requestAnimationFrame(reportHeight);
            };
            try {
              if (!globalThis.mermaid) throw new Error('Bundled Mermaid renderer did not load.');
              globalThis.mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: 'base',
                themeVariables: {
                  background: 'transparent',
                  mainBkg: '\(nodeFill)',
                  primaryColor: '\(nodeFill)',
                  primaryBorderColor: '\(nodeBorder)',
                  primaryTextColor: '\(foreground)',
                  secondaryColor: '\(background)',
                  tertiaryColor: '\(background)',
                  lineColor: '\(line)',
                  textColor: '\(foreground)',
                  edgeLabelBackground: '\(background)',
                  clusterBkg: '\(background)',
                  clusterBorder: '\(nodeBorder)',
                  fontFamily: '-apple-system, BlinkMacSystemFont, SF Pro Text, sans-serif'
                }
              });
              globalThis.mermaid.render('cribble-mermaid-' + Math.random().toString(36).slice(2), source)
                .then(({ svg }) => {
                  root.innerHTML = svg;
                  requestAnimationFrame(reportHeight);
                })
                .catch(showError);
              new ResizeObserver(reportHeight).observe(document.body);
            } catch (error) {
              showError(error);
            }
          </script>
        </body>
        </html>
        """
    }
}
