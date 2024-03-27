import Foundation
import WebKit

/// PipeablePage provides methods to interact with a web page loaded in the
/// webview.
/// It can be constructed by wrapping an existing WKWebView using a constructor
/// or by using a `PipeableWebView` and acquiring it from there.
/// Note that in the case of using a constructor, you need to make sure that
/// the lifecycle of the `PipeablePage` is managed correctly.
///
/// Example:
/// ```swift
/// let webView = PipeableWebView()
/// let page = webView.page
///
/// try? await page.goto("https://example.com", waitUntil: .load)
/// let exampleEl = try? await page.querySelector("input[name='example']")
/// ```
public class PipeablePage {
    var webView: WKWebView
    var frame: WKFrameInfo?

    private var delegate: PipeablePageDelegate?
    var frameInfoResolver: FrameInfoResolver = .init()
    var pageLoadState: PageLoadState
    var lastHTTPResponse: LastHTTPResponse = .init()

    class FrameInfoResolver {
        var continuations: [String: CheckedContinuation<PipeablePage?, Error>] = [:]
        var frameInfos: [String: WKFrameInfo?] = [:]

        var synchronizationQueue = DispatchQueue(label: "wkframeResolver")
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

    /// Adds a script to be included in any page and frame loaded in  the webview.
    /// - Parameters:
    ///   - contents: The script content to be added.
    ///   - injectionTime: Specifies when the script should be injected into the web page. Defaults to `.atDocumentEnd`.
    ///   - forMainFrameOnly: Boolean indicating whether the script should be injected into all frames or just the main frame. Defaults to `false`.
    public func addUserScript(_ contents: String, injectionTime: WKUserScriptInjectionTime = .atDocumentEnd, forMainFrameOnly: Bool = false) {
        let userScript = WKUserScript(
            source: contents,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly
        )

        webView.configuration.userContentController.addUserScript(userScript)
    }

    /// Submits the currently active form on the page.
    /// Useful when there is no submit button and a form is only submitted from the mobile keyboard.
    /// - Returns: A boolean indicating whether the form submission was successful.
    /// - Throws: An error if JavaScript evaluation fails.
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

    /// Retrieves the current URL of the web view.
    /// - Returns: The current URL, or `nil` if no URL is loaded.
    @MainActor
    public func url() -> URL? {
        return webView.url
    }
}

public enum PipeableError: Error {
    /// Navigation failed with the given error
    case navigationError(String)
    
    /// Queried element not found
    case elementNotFound
    
    /// Response could not be parsed
    case invalidResponse
    
    /// Incorrectly supplied parameter to call
    case invalidParameter(String)
    
    /// Received a fatal error and Pipeable cannot continue execution.
    /// For example, we couldn't create a JSHandle for a response.
    case fatalError(String)    
}
