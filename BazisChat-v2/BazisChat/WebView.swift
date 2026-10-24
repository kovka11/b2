import SwiftUI
import WebKit

/// A webnézet és a SwiftUI közötti állapot.
final class WebState: ObservableObject {
    @Published var loadFailed = false
    @Published var progress: Double = 0
    @Published var themeColor: Color?
    weak var webView: WKWebView?

    func reload() {
        loadFailed = false
        guard let webView else { return }
        if webView.url == nil {
            webView.load(URLRequest(url: startURL))
        } else {
            webView.reload()
        }
    }
}

struct WebView: UIViewRepresentable {
    let state: WebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default() // belépés és süti megmarad

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Húzd le a frissítéshez
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.handleRefresh(_:)),
                          for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.attach(webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private let state: WebState
        private weak var webView: WKWebView?
        private var progressObservation: NSKeyValueObservation?
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(state: WebState) {
            self.state = state
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            state.webView = webView
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.state.progress = view.estimatedProgress
                }
            }
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            state.reload()
        }

        // MARK: - Betöltés és hibák

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            state.loadFailed = false
            updateThemeColor(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleFailure(error)
        }

        private func handleFailure(_ error: Error) {
            webView?.scrollView.refreshControl?.endRefreshing()
            let nsError = error as NSError
            // Megszakított betöltés (pl. új link vagy letöltés indult) nem hiba
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
            state.loadFailed = true
        }

        // MARK: - Színek

        private func updateThemeColor(from webView: WKWebView) {
            let js = """
            (function () {
              var m = document.querySelector('meta[name="theme-color"]');
              if (m && m.content) { return m.content; }
              var el = document.body || document.documentElement;
              return el ? getComputedStyle(el).backgroundColor : '';
            })();
            """
            webView.evaluateJavaScript(js) { [weak self, weak webView] result, _ in
                guard let self, let css = result as? String, let color = UIColor(css: css) else { return }
                self.state.themeColor = Color(color)
                webView?.underPageBackgroundColor = color
            }
        }

        // MARK: - Linkek

        // A bazischat.eu linkjei az appban nyílnak, a többi a Safariban.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = target.scheme?.lowercased() ?? ""
            let host = target.host?.lowercased() ?? ""
            let isInternal = host == "bazischat.eu" || host.hasSuffix(".bazischat.eu")

            if ["mailto", "tel", "sms"].contains(scheme) {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            } else if navigationAction.navigationType == .linkActivated && !isInternal {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // target="_blank" linkek ugyanabban a nézetben nyílnak
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: - Fájlletöltés

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse,
               let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
               disposition.lowercased().hasPrefix("attachment") {
                decisionHandler(.download)
                return
            }
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                completionHandler(nil)
                return
            }
            let destination = folder.appendingPathComponent(suggestedFilename)
            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        // Letöltés után megjelenik a megosztás menü (Mentés a Fájlokba, Fotók, AirDrop...)
        func downloadDidFinish(_ download: WKDownload) {
            guard let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            UIHelper.presentShareSheet(for: file)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }

        // MARK: - Kamera és mikrofon

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let host = origin.host.lowercased()
            if host == "bazischat.eu" || host.hasSuffix(".bazischat.eu") {
                decisionHandler(.grant)
            } else {
                decisionHandler(.deny)
            }
        }

        // MARK: - JavaScript alert / confirm

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            UIHelper.presentAlert(message: message, withCancel: false) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            UIHelper.presentAlert(message: message, withCancel: true, completion: completionHandler)
        }
    }
}
