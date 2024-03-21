import Foundation
import WebKit

public class PipeablePage {
    var webView: WKWebView
    var frame: WKFrameInfo?

    private var delegate: PipeablePageDelegate?
    var frameInfoResolver: FrameInfoResolver = .init()
    private var pageLoadState: PageLoadState

    class FrameInfoResolver {
        var continuations: [String: CheckedContinuation<PipeablePage?, Error>] = [:]
        var frameInfos: [String: WKFrameInfo?] = [:]

        var synchronizationQueue = DispatchQueue(label: "wkframeResolver")
    }

    actor LastHTTPResponse {
        var lastHTTPResponse: PipeableHTTPResponse?

        func setLastHTTPResponse(_ response: PipeableHTTPResponse?) {
            lastHTTPResponse = response
        }
    }

    private var lastHTTPResponse: LastHTTPResponse = .init()

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
            if ctx == "pipeable" {
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
                    } else if name == "log" {
                        guard let message = payload["state"] as? String else {
                            return
                        }

                        print("[CONSOLE] \(message)")
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

    public convenience init(_ webView: WKWebView, debugPrintConsoleLogs: Bool? = nil) {
        self.init(webView, nil, debugPrintConsoleLogs: debugPrintConsoleLogs)
    }

    init(_ webView: WKWebView, _ frame: WKFrameInfo? = nil, debugPrintConsoleLogs: Bool? = nil) {
        self.webView = webView
        self.frame = frame

        let config = webView.configuration

        var contents: String?

        // Logging override.
        if debugPrintConsoleLogs ?? false {
            let loggingOverrideScript = WKUserScript(
                source:
                """
                origConsoleLog = window.console.log;
                window.console.log = function(message) {
                    window.webkit.messageHandlers.handler.postMessage({
                        ctx: 'pipeable',
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

        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: PipeablePage.self)
        #endif

        let pathInFramework = bundle.path(forResource: "pipeable", ofType: "js")

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

        pageLoadState = PageLoadState()

        // This is the main frame / page.
        if frame == nil {
            delegate = PipeablePageDelegate(pageLoadState, lastHTTPResponse)
            self.webView.navigationDelegate = delegate
            self.webView.configuration.userContentController.add(
                ContentController(frameInfoResolver, pageLoadState),
                name: "handler"
            )
        }
    }

    deinit {
        // Remove outselves.
        if frame == nil {
            // Controller.
            self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "handler")

            // Delegate.
            self.webView.navigationDelegate = nil
        }
    }

    /// Navigates to the given URL.
    /// - Parameters:
    ///  - url: The URL to navigate to.
    ///  - waitUntil: When to consider navigation as finished, defaults to `.load`.
    ///  - timeout: Maximum time to wait for the navigation to finish, defaults to 30000ms.
    ///  - Returns: The response of the navigation - HTTP status code and
    ///  headers. Can return nil if the response is not available. For example,
    ///  if the navigation is to a non-HTTP URL: about:blank, data:, etc.
    ///  - Throws: PipeableError.navigationError if the navigation fails.

    public func goto(_ url: String, waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws -> PipeableHTTPResponse? {
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

        let response = await lastHTTPResponse.lastHTTPResponse
        return response
    }

    public func addUserScript(_ contents: String, injectionTime: WKUserScriptInjectionTime = .atDocumentEnd, forMainFrameOnly: Bool = false) {
        let userScript = WKUserScript(
            source: contents,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly
        )

        webView.configuration.userContentController.addUserScript(userScript)
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

        try await pageLoadState.waitForLoadStateChange(
            predicate: { state, _ in
                state.rawValue >= LoadState.fromWaitUntil(waitUntil).rawValue
            },
            timeout: timeout
        )
    }

    // TODO: Implement shorthards for predicates -- string matching, regex matching
    public func waitForURL(
        _ predicate: @escaping (String) -> Bool,
        waitUntil: WaitUntilOption = .load,
        timeout: Int = 30000,
        ignoreNavigationErrors: Bool = false
    ) async throws {
        try await pageLoadState.waitForLoadStateChange(
            predicate: { state, url in
                if let url = url {
                    return state.rawValue >= LoadState.fromWaitUntil(waitUntil).rawValue && predicate(url)
                } else {
                    return false
                }
            },
            timeout: timeout,
            ignoreNavigationErrors: ignoreNavigationErrors
        )
    }

    public func waitForXHR(_ url: String, timeout: Int = 30000) async throws -> XHRResult? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForXHR(url, timeout);
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

    public func submitActiveForm() async throws -> Bool {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.submitActiveForm();
            """,
            arguments: [:],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        return result as? Bool ?? false
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

public struct PipeableHTTPResponse: Decodable {
    public var status: Int
    public var headers: [String: String]
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
