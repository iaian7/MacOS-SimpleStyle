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
        
        // Describe an element as { tag, id, classes }
        window.csseditDescribeEl = function(el) {
            if (!el || !el.tagName) return null;
            const classes = [];
            if (el.classList && el.classList.length > 0) {
                for (let i = 0; i < el.classList.length; i++) {
                    const c = el.classList[i];
                    if (c !== 'cssedit-xray-hover' && c !== 'cssedit-xray-selected') {
                        classes.push(c);
                    }
                }
            }
            return {
                tag: el.tagName.toLowerCase(),
                id: el.id || '',
                classes: classes
            };
        };
        
        // Return an array of child indices from <html> down to el (inclusive).
        // E.g. <html>'s third child's first child -> [2, 0].
        window.csseditPathTo = function(el) {
            const path = [];
            let cur = el;
            while (cur && cur.parentElement) {
                const parent = cur.parentElement;
                const idx = Array.prototype.indexOf.call(parent.children, cur);
                path.unshift(idx);
                cur = parent;
            }
            return path;
        };
        
        // Resolve a path back to an element.
        window.csseditElFromPath = function(path) {
            let cur = document.documentElement;
            if (!Array.isArray(path)) return null;
            for (let i = 0; i < path.length; i++) {
                if (!cur || !cur.children || path[i] >= cur.children.length) return null;
                cur = cur.children[path[i]];
            }
            return cur;
        };
        
        // Build the ancestor chain (from <html> down to el inclusive) as descriptors.
        window.csseditAncestorsOf = function(el) {
            const chain = [];
            let cur = el;
            while (cur && cur.tagName) {
                chain.unshift(window.csseditDescribeEl(cur));
                cur = cur.parentElement;
            }
            return chain;
        };
        
        // Apply the persistent green outline to el (clearing any previous selection).
        window.csseditApplySelection = function(el) {
            if (window.csseditSelectedEl && window.csseditSelectedEl !== el) {
                window.csseditSelectedEl.classList.remove('cssedit-xray-selected');
            }
            window.csseditSelectedEl = el || null;
            if (el && el.classList) {
                el.classList.add('cssedit-xray-selected');
                if (typeof el.scrollIntoView === 'function') {
                    try { el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'auto' }); } catch (_) {}
                }
            }
        };
        
        // Programmatic: select an element by its path and notify Swift.
        window.csseditSelectByPath = function(path) {
            const el = window.csseditElFromPath(path);
            if (!el) return;
            window.csseditApplySelection(el);
            const ancestors = window.csseditAncestorsOf(el);
            const elPath = window.csseditPathTo(el);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cssedit) {
                window.webkit.messageHandlers.cssedit.postMessage({
                    type: 'elementSelected',
                    tag: ancestors.length ? ancestors[ancestors.length - 1].tag : '',
                    id: ancestors.length ? ancestors[ancestors.length - 1].id : '',
                    classes: ancestors.length ? ancestors[ancestors.length - 1].classes : [],
                    path: elPath,
                    ancestors: ancestors
                });
            }
        };

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
            window.csseditApplySelection(el);
            
            const ancestors = window.csseditAncestorsOf(el);
            const path = window.csseditPathTo(el);
            const me = ancestors.length ? ancestors[ancestors.length - 1] : { tag: '', id: '', classes: [] };
            
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cssedit) {
                window.webkit.messageHandlers.cssedit.postMessage({
                    type: 'elementSelected',
                    tag: me.tag,
                    id: me.id,
                    classes: me.classes,
                    path: path,
                    ancestors: ancestors
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
            isXRayEnabled: viewModel.isXRayEnabled,
            pendingSelectionRequest: viewModel.pendingXRayPathRequest
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
        private var lastSelectionRequestID: UUID?

        func sync(urlString: String, reloadToken: UUID, css: String, isXRayEnabled: Bool, pendingSelectionRequest: XRaySelectionRequest?) {
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
            
            if let request = pendingSelectionRequest, request.id != lastSelectionRequestID {
                lastSelectionRequestID = request.id
                selectElement(at: request.path)
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
            let path = (body["path"] as? [Int]) ?? []
            let rawAncestors = (body["ancestors"] as? [[String: Any]]) ?? []
            
            guard !tag.isEmpty else { return }
            
            let ancestors: [XRayElementInfo] = rawAncestors.compactMap { dict in
                let t = (dict["tag"] as? String) ?? ""
                let i = (dict["id"] as? String) ?? ""
                let c = (dict["classes"] as? [String]) ?? []
                guard !t.isEmpty else { return nil }
                return XRayElementInfo(tag: t, id: i, classes: c)
            }
            
            let info = XRayElementInfo(tag: tag, id: id, classes: classes)
            parent?.viewModel.handleXRayElementSelected(info, path: path, ancestors: ancestors)
        }
        
        // Tell the webview to programmatically select an element by its DOM path.
        func selectElement(at path: [Int]) {
            guard let webView else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: path, options: []),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.csseditSelectByPath(\(json));", completionHandler: nil)
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
