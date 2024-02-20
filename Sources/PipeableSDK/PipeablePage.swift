import Foundation
import WebKit

// swiftlint:disable type_body_length
// swiftlint:disable file_length

public class PipeablePage {
    var webView: WKWebView
    var frame: WKFrameInfo?
    private var delegate: Delegate?

    var frameInfoResolver: FrameInfoResolver = .init()
    private var pageLoadState: PageLoadState

    class FrameInfoResolver {
        var continuations: [String: CheckedContinuation<PipeablePage?, Error>] = [:]
        var frameInfos: [String: WKFrameInfo?] = [:]

        var synchronizationQueue = DispatchQueue(label: "wkframeResolver")
    }

    class Delegate: NSObject, WKNavigationDelegate {
        private var loadPageState: PageLoadState

        init(_ loadPageSignal: PageLoadState) {
            loadPageState = loadPageSignal
        }

        func webView(_: WKWebView, didFinish _: WKNavigation) {
            // Used to fire the DOMContentloaded here, but it actually is not really domcontentloaded, more like .load
            // Right now everything is fired from JS, but we might want to fire load here as well, just in case
            // some script deregisters all listeners on boot.
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation) {
            loadPageState.changeState(state: .notloaded, url: webView.url?.absoluteString)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation, withError error: Error) {
            loadPageState.error(
                error: PipeableError.navigationError(error.localizedDescription),
                url: webView.url?.absoluteString
            )
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation, withError error: Error) {
            loadPageState.error(
                error: PipeableError.navigationError(error.localizedDescription),
                url: webView.url?.absoluteString
            )
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

        func webView(_: WKWebView, decidePolicyFor _: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }
    }

    class ContentController: NSObject, WKScriptMessageHandler {
        private var frameInfoResolver: FrameInfoResolver
        private var pageLoadState: PageLoadState

        init(_ frameInfoResolver: FrameInfoResolver, _ pageLoadState: PageLoadState) {
            self.frameInfoResolver = frameInfoResolver
            self.pageLoadState = pageLoadState
        }

        // swiftlint:disable:next cyclomatic_complexity
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: AnyObject] else {
                return
            }
            guard let ctx = dict["ctx"] as? String, let name = dict["name"] as? String else {
                return
            }

            // TODO: Somehow add here schema validation for messages
            if ctx == "sophia" {
                print("dict " + String(describing: dict))
                if let payload = dict["payload"] as? [String: AnyObject] {
                    if name == "frameInfoId" {
                        guard let requestId = payload["requestId"] as? String else {
                            return
                        }

                        frameInfoResolver.synchronizationQueue.sync {
                            if let continuation = frameInfoResolver.continuations[requestId] {
                                guard let webView = message.frameInfo.webView else {
                                    // TODO: Handle this.
                                    return
                                }
                                continuation.resume(returning: PipeablePage(webView, message.frameInfo))
                            } else {
                                self.frameInfoResolver.frameInfos[requestId] = message.frameInfo
                            }
                        }
                    } else if name == "pageLoadStateChange" {
                        guard let rawState = payload["state"] as? String else {
                            return
                        }

                        guard let url = payload["url"] as? String else {
                            return
                        }

                        guard let state = LoadState.fromString(rawState) else {
                            // LOG ERROR once we decide on error logging. This is a problem between the JS and Swift code.
                            return
                        }

                        pageLoadState.changeState(state: state, url: url)
                    }
                }
            }
        }
    }

    public enum WaitUntilOption: String {
        case load
        case domcontentloaded
        case networkidle
    }

    public init(_ webView: WKWebView, _ frame: WKFrameInfo? = nil, debugPrintConsoleLogs: Bool? = nil) {
        self.webView = webView
        self.frame = frame

        let config = webView.configuration

        var contents: String?

        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: PipeablePage.self)
        #endif

        let pathInFramework = bundle.path(forResource: "sophia", ofType: "js")

        if let filepath = pathInFramework {
            contents = try? String(contentsOfFile: filepath, encoding: .utf8)
        }

        if let unwrappedContents = contents {
            let userScriptIframe = WKUserScript(
                source: unwrappedContents,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(userScriptIframe)
        } else {
            fatalError("Could not find bundled JS")
        }

        // Logging override.
        if debugPrintConsoleLogs ?? false {
            let loggingOverrideScript = WKUserScript(
                source:
                """
                origConsoleLog = window.console.log;
                window.console.log = function(message) {
                    window.webkit.messageHandlers.handler.postMessage({
                        ctx: 'sophia',
                        name: 'log',
                        payload: { message }
                    });

                    origConsoleLog.apply(null, arguments);
                };
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(loggingOverrideScript)
        }
        pageLoadState = PageLoadState()

        // This is the main frame / page.
        if frame == nil {
            delegate = Delegate(pageLoadState)
            self.webView.navigationDelegate = delegate
            self.webView.configuration.userContentController.add(
                ContentController(frameInfoResolver, pageLoadState),
                name: "handler"
            )
        }
    }

    deinit {
        if frame == nil {
            self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "handler")
        }
    }

    public func goto(_ url: String, waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
        print("page goto \(url) timeout \(timeout) waitUntil \(waitUntil)")

        pageLoadState.changeState(state: .notloaded, url: nil)

        if let urlObj = URL(string: url) {
            let request = URLRequest(url: urlObj, timeoutInterval: TimeInterval(timeout) / 1000)

            DispatchQueue.main.async {
                self.webView.load(request)
            }
        } else {
            throw PipeableError.navigationError("Incorrect URL \(url)")
        }

        try await waitForLoadState(waitUntil: waitUntil, timeout: timeout)
    }

    public func reload(waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
        pageLoadState.changeState(state: .notloaded, url: nil)
        await webView.reload()
        return try await waitForLoadState(waitUntil: waitUntil, timeout: timeout)
    }

    public func waitForLoadState(waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
        if frame != nil {
            // Iframes are already loaded, if we can address them.
            // TODO: This is only correct for domcontentloaded, load and networkidle still need handling for iframes.
            return
        }

        // If we're in a higher state than what we're waiting for already, return immediately.
        if pageLoadState.state.rawValue >= LoadState.fromWaitUntil(waitUntil).rawValue {
            return
        }

        // Otherwise, wait until we get there or we time out.

        // Since there is a potential race condition that can lead to double
        // "resume" calls on the continuation, we need to ensure that the
        // continuation is only resumed once. We guard this by running resumes
        // in a queue and using a helper.
        class ResumeOnce {
            let queueForResuming = DispatchQueue(label: "waitForLoadState")
            var isResumed = false

            func resume(action: () -> Void) {
                queueForResuming.sync {
                    if !isResumed {
                        isResumed = true
                        action()
                    }
                }
            }
        }

        let resumeOnce = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var timeoutTask: Task<Void, Never>?

            let removeListener = self.pageLoadState.subscribeToLoadStateChange { state, _, error in
                if let error = error {
                    resumeOnce.resume {
                        continuation.resume(throwing: error)
                    }

                    // Clean up timer.
                    timeoutTask?.cancel()

                    return true
                } else if state.rawValue >= LoadState.fromWaitUntil(waitUntil).rawValue {
                    resumeOnce.resume {
                        continuation.resume(returning: ())
                    }

                    // Clean up timer.
                    timeoutTask?.cancel()
                    return true
                }

                return false
            }

            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout) * 1000000)
                } catch {
                    // If the sleep is cancelled, then we move to
                }
                removeListener()

                resumeOnce.resume {
                    continuation.resume(throwing: PipeableError.navigationError("The request timed out."))
                }
            }
        }
    }

    // TODO: Implement timeout
    // TODO: Implement shorthards for predicates -- string matching, regex matching
    public func waitForURL(_ predicate: @escaping (String) -> Bool, waitUntil: WaitUntilOption = .load) async throws {
        if let currentUrl = await url()?.absoluteString {
            if predicate(currentUrl) {
                return
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = self.pageLoadState.subscribeToLoadStateChange { state, url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return true
                } else if
                    let url = url,
                    state.rawValue >= LoadState.fromWaitUntil(waitUntil).rawValue,
                    predicate(url)
                {
                    continuation.resume(returning: ())
                    return true
                }

                return false
            }
        }
    }

    public func querySelector(_ selector: String) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$(selector);
            """,
            arguments: ["selector": selector],
            in: frame,
            contentWorld: WKContentWorld.page
        )
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }

    public func querySelectorAll(_ selector: String) async throws -> [PipeableElement] {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$$(selector);
            """,
            arguments: ["selector": selector],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        print(result ?? "No result")

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self, elementId)
            }
        }

        return []
    }

    public func xpathSelector(_ xpath: String) async throws -> [PipeableElement] {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$x(xpath);
            """,
            arguments: ["xpath": xpath],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        print(result ?? "No result")

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self, elementId)
            }
        }

        return []
    }

    public func waitForXPath(_ xpath: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForXPath(xpath, opts);
            """,
            arguments: [
                "xpath": xpath,
                "opts": [
                    "timeout": String(timeout),
                    "visible": visible,
                ] as [String: Any],
            ],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        print("Wait for XPath result \(result ?? "")")

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }

    public func waitForSelector(_ selector: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForSelector(selector, opts);
            """,
            arguments: [
                "selector": selector,
                "opts": [
                    "timeout": String(timeout),
                    "visible": visible,
                ] as [String: Any],
            ],
            in: frame,
            contentWorld: WKContentWorld.page
        )
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }

    public func waitForXHR(_ url: String, timeout: Int = 30000) async throws -> XHRResult? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForXHR(url, timeout);
            """,
            arguments: ["url": url, "timeout": timeout],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        guard let stringResult = result as? String else {
            throw PipeableError.invalidResponse
        }

        guard let data = stringResult.data(using: .utf8) else {
            throw PipeableError.invalidResponse
        }

        let xhrResult = try JSONDecoder().decode(XHRResult.self, from: data)
        return xhrResult
    }

    public func evaluate(_ javascript: String) async throws -> Any? {
        let evaluationScript = """
            (function () {
                var result = (() => \(javascript))();
                return result !== undefined ? result : null;
            })();
        """

        let result = try await webView.evaluateJavaScript(
            evaluationScript,
            in: frame,
            contentWorld: WKContentWorld.page
        )

        return result
    }

    // TODO: Figure out error handling here.
    public func loadCookies(fromJSONString jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {
            return
        }

        guard let cookieArray = try? JSONSerialization.jsonObject(
            with: data,
            options: []
        ) as? [[String: AnyObject]] else {
            return
        }

        for cookieDict in cookieArray {
            var cookieProperties: [HTTPCookiePropertyKey: Any] = [:]
            cookieProperties[.name] = cookieDict["name"] as? String ?? ""
            cookieProperties[.value] = cookieDict["value"] as? String ?? ""
            cookieProperties[.domain] = cookieDict["domain"] as? String ?? ""
            cookieProperties[.path] = cookieDict["path"] as? String ?? "/"
            // cookieProperties[.expires] = Date().addingTimeInterval(60 * 60 * 24 * 7) // One week

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            if let cookie = HTTPCookie(properties: cookieProperties) {
                cookieStore.setCookie(cookie)
            }
        }
    }

    @MainActor
    public func url() -> URL? {
        return webView.url
    }
}

public struct XHRResult: Decodable {
    public enum ResponseType: String, Decodable {
        case none = ""
        case text
        case arraybuffer
        case blob
        case document
        case json
    }

    public var status: Int
    public var body: String
    public var headers: String
    public var url: String
    public var responseType: ResponseType
}

// TODO: This is not complete or valid
enum PipeableError: Error {
    case navigationError(String)
    case elementNotFound
    case invalidResponse
    case invalidParameter(String)
    case fatalError(String)
    case initializationError
}

func randomString(length: Int) -> String {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    // swiftlint:disable:next force_unwrapping
    return String((0 ..< length).map { _ in characters.randomElement()! })
}
