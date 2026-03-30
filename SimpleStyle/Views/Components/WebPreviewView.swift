import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.userContentController.add(context.coordinator, name: "cssedit")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.sync(
            urlString: viewModel.previewURLString,
            reloadToken: viewModel.reloadToken,
            css: viewModel.previewCSS
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        private var lastLoadedURLString = ""
        private var lastInjectedCSS = ""
        private var lastReloadToken = UUID()
        private var pendingCSS = ""
        private var isLoading = false

        func sync(urlString: String, reloadToken: UUID, css: String) {
            pendingCSS = css

            if reloadToken != lastReloadToken {
                lastReloadToken = reloadToken
                load(urlString: urlString, force: true)
                return
            }

            if urlString != lastLoadedURLString {
                load(urlString: urlString, force: false)
                return
            }

            if css != lastInjectedCSS {
                inject(css: css)
            }
        }

        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Reserved for v2 element-click messaging
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            inject(css: pendingCSS)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        // MARK: - Private
        private func load(urlString: String, force: Bool) {
            guard let webView,
                  let url = URL(string: urlString),
                  let scheme = url.scheme else { return }

            guard ["http", "https", "file"].contains(scheme.lowercased()) else { return }

            if !force, urlString == lastLoadedURLString { return }

            lastLoadedURLString = urlString
            lastInjectedCSS = ""
            webView.load(URLRequest(url: url))
        }

        private func inject(css: String) {
            guard let webView, !isLoading else { return }

            guard let jsonData = try? JSONEncoder().encode(css),
                  let encodedCSS = String(data: jsonData, encoding: .utf8) else { return }

            let script = """
            (function() {
                const css = \(encodedCSS);
                let style = document.getElementById('cssedit-injected');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'cssedit-injected';
                    document.head.appendChild(style);
                }
                style.textContent = css;
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, _ in
                self?.lastInjectedCSS = css
            }
        }
    }
}
