import Foundation
import WebKit

class PipeablePageDelegate: NSObject, WKNavigationDelegate {
    private var loadPageState: PageLoadState
    private var lastHTTPResponse: PipeablePage.LastHTTPResponse

    init(_ loadPageSignal: PageLoadState, _ lastHTTPResponse: PipeablePage.LastHTTPResponse) {
        loadPageState = loadPageSignal
        self.lastHTTPResponse = lastHTTPResponse
    }

    func webView(_: WKWebView, didFinish _: WKNavigation) {
        // Used to fire the DOMContentloaded here, but it actually is not really domcontentloaded, more like .load
        // Right now everything is fired from JS, but we might want to fire load here as well, just in case
        // some script deregisters all listeners on boot.
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation) {
        loadPageState.changeState(state: .notloaded, url: nil)
        Task { await lastHTTPResponse.setLastHTTPResponse(nil) }
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation, withError error: Error) {
        loadPageState.error(
            error: PipeableError.navigationError(error.localizedDescription),
            url: webView.url?.absoluteString
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation, withError error: Error) {
        // TODO: Figure out how to deal with Apple Login...
//        loadPageState.error(
//            error: PipeableError.navigationError(error.localizedDescription),
//            url: webView.url?.absoluteString
//        )
    }

    func webView(_: WKWebView, didReceive _: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPageState.error(error: PipeableError.navigationError("Terminated"), url: webView.url?.absoluteString)
    }

    func webView(_: WKWebView, decidePolicyFor _: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            if navigationResponse.isForMainFrame {
                // Collecting all headers
                let allHeaders = httpResponse.allHeaderFields
                // Casting to [String: String] if necessary. Note: Some header field values might not be String.
                let headersDictionary: [String: String] =
                    allHeaders.reduce(into: [String: String]()) { result, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            result[key] = value
                        }
                    }

                let httpResponse = PipeableHTTPResponse(
                    status: httpResponse.statusCode,
                    headers: headersDictionary
                )

                Task { await lastHTTPResponse.setLastHTTPResponse(httpResponse) }
            }
        }

        decisionHandler(.allow)
    }
}
