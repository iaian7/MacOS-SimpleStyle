import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.userContentController.add(context.coordinator, name: "cssedit")

        let xrayScriptSource = """
        window.csseditXRayEnabled = false;
        window.csseditSelectedEl = null;
        
        try {
            const xrayStyle = document.createElement('style');
            xrayStyle.textContent = `
                .cssedit-xray-hover {
                    outline: 2px solid #007aff !important;
                    outline-offset: -2px !important;
                    cursor: crosshair !important;
                }
                .cssedit-xray-selected {
                    outline: 2px solid #34c759 !important;
                    outline-offset: -2px !important;
                }
            `;
            (document.head || document.documentElement).appendChild(xrayStyle);
        } catch (e) {
            console.error('CSS Edit X-Ray: Failed to inject style tag.', e);
        }

        document.addEventListener('mouseover', function(e) {
            if (!window.csseditXRayEnabled) return;
            if (e.target) e.target.classList.add('cssedit-xray-hover');
        }, true);
        
        document.addEventListener('mouseout', function(e) {
            if (!window.csseditXRayEnabled) return;
            if (e.target) e.target.classList.remove('cssedit-xray-hover');
        }, true);
        
        document.addEventListener('click', function(e) {
            if (!window.csseditXRayEnabled) return;
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            
            if (!e.target) return;
            const el = e.target;
            el.classList.remove('cssedit-xray-hover');
            
            // Clear previous selection
            if (window.csseditSelectedEl && window.csseditSelectedEl !== el) {
                window.csseditSelectedEl.classList.remove('cssedit-xray-selected');
            }
            window.csseditSelectedEl = el;
            el.classList.add('cssedit-xray-selected');
            
            const tag = el.tagName ? el.tagName.toLowerCase() : '';
            const id = el.id || '';
            let classes = [];
            if (el.classList && el.classList.length > 0) {
                for (let i = 0; i < el.classList.length; i++) {
                    const c = el.classList[i];
                    if (c !== 'cssedit-xray-hover' && c !== 'cssedit-xray-selected') {
                        classes.push(c);
                    }
                }
            }
            
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cssedit) {
                window.webkit.messageHandlers.cssedit.postMessage({
                    type: 'elementSelected',
                    tag: tag,
                    id: id,
                    classes: classes
                });
            }
        }, { capture: true, passive: false });
        
        // Suppress mousedown/mouseup so links/buttons don't activate
        ['mousedown', 'mouseup', 'auxclick', 'dblclick'].forEach(function(name) {
            document.addEventListener(name, function(e) {
                if (!window.csseditXRayEnabled) return;
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
            }, { capture: true, passive: false });
        });
        """
        
        let userScript = WKUserScript(source: xrayScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(
            urlString: viewModel.previewURLString,
            reloadToken: viewModel.reloadToken,
            css: viewModel.previewCSS,
            isXRayEnabled: viewModel.isXRayEnabled
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var parent: WebPreviewView?

        private var lastLoadedURLString = ""
        private var lastInjectedCSS = ""
        private var lastReloadToken = UUID()
        private var pendingCSS = ""
        private var isLoading = false
        private var lastXRayEnabled = false

        func sync(urlString: String, reloadToken: UUID, css: String, isXRayEnabled: Bool) {
            pendingCSS = css

            lastXRayEnabled = isXRayEnabled
            let jsValue = isXRayEnabled ? "true" : "false"
            webView?.evaluateJavaScript("window.csseditXRayEnabled = \(jsValue);", completionHandler: nil)

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
            guard message.name == "cssedit",
                  let body = message.body as? [String: Any] else {
                return
            }
            
            let tag = (body["tag"] as? String) ?? ""
            let id = (body["id"] as? String) ?? ""
            let classes = (body["classes"] as? [String]) ?? []
            
            guard !tag.isEmpty else { return }
            
            let info = XRayElementInfo(tag: tag, id: id, classes: classes)
            parent?.viewModel.handleXRayElementSelected(info)
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            inject(css: pendingCSS)
            let jsValue = lastXRayEnabled ? "true" : "false"
            webView.evaluateJavaScript("window.csseditXRayEnabled = \(jsValue);", completionHandler: nil)
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
