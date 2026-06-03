import Foundation
import WebKit

/// Validates Mermaid by actually parsing it in a headless WKWebView with the
/// bundled `mermaid.min.js` (design plan §7.4) — catching syntax the cheap
/// structural check in `OutputValidator` can't.
///
/// **Best-effort and conservative:** any infrastructure failure (renderer missing,
/// load failure, JS error, etc.) returns `true` so a flaky validator can never
/// block legitimately-generated diagrams. It only returns `false` when Mermaid
/// itself definitively rejects the source.
@MainActor
final class MermaidRenderValidator {
    static let shared = MermaidRenderValidator()

    private var webView: WKWebView?
    private var ready = false
    private var loadDelegate: LoadDelegate?

    func validate(_ source: String) async -> Bool {
        guard await ensureReady(), let webView else { return true }
        // `mermaid.parse` throws on invalid input; newer versions return a Promise.
        let js = """
        try {
          const r = mermaid.parse(src);
          if (r && typeof r.then === 'function') { await r; }
          return true;
        } catch (e) { return false; }
        """
        let result = try? await webView.callAsyncJavaScript(
            js, arguments: ["src": source], in: nil, contentWorld: .page
        )
        return (result as? Bool) ?? true
    }

    private func ensureReady() async -> Bool {
        if ready { return true }
        let script = MermaidHTML.script()
        guard !script.contains("__cribbleMermaidMissing") else { return false }

        let webView = WKWebView(frame: .zero)
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        self.webView = webView
        self.loadDelegate = delegate

        let html = """
        <!doctype html><html><head><meta charset="utf-8"><script>\(script)</script></head>
        <body><script>
          try { globalThis.mermaid && globalThis.mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' }); } catch (e) {}
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        let ok = await delegate.waitUntilLoaded()
        ready = ok
        return ok
    }

    @MainActor
    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var finished = false

        func waitUntilLoaded() async -> Bool {
            if finished { return true }
            return await withCheckedContinuation { continuation = $0 }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { resume(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { resume(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { resume(false) }

        private func resume(_ value: Bool) {
            finished = true
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
