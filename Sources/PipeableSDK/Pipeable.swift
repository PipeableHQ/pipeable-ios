import Foundation
import WebKit

// swiftlint:disable type_body_length
// swiftlint:disable file_length

public class PipeablePage {
    var webView: WKWebView
    var frame: WKFrameInfo?
    private var delegate: Delegate?

    var frameInfoResolver: FrameInfoResolver = .init()
    var loadPageSignal: LoadPageSignal

    class FrameInfoResolver {
        var continuations: [String: CheckedContinuation<PipeablePage?, Error>] = [:]
        var frameInfos: [String: WKFrameInfo?] = [:]

        var synchronizationQueue = DispatchQueue(label: "wkframeResolver")
    }

    class LoadPageSignal {
        var isPageLoaded = false
        var loadCompletion: CheckedContinuation<Void, Error>?

        // TODO: Make the predicate actually not just be a function, but string | regex | function
        var waitForURLContinuations: [String: CheckedContinuation<Void, Error>] = [:]
        var waitForURLPredicates: [String: (String) -> Bool] = [:]
        let synchronizationQueue = DispatchQueue(label: "waitForURL")

        func addWaitForURL(_ predicate: @escaping (String) -> Bool, continuation: CheckedContinuation<Void, Error>) {
            synchronizationQueue.sync {
                var uniqueKey: String

                repeat {
                    uniqueKey = randomString(length: 10)
                } while self.waitForURLPredicates.keys.contains(uniqueKey)

                let hash = uniqueKey

                self.waitForURLContinuations[hash] = continuation
                self.waitForURLPredicates[hash] = predicate
            }
        }

        func signalURLLoadedResult(_ url: String?, withError error: Error? = nil) {
            if error == nil {
                isPageLoaded = true
                loadCompletion?.resume(returning: ())
                loadCompletion = nil
            } else {
                isPageLoaded = false
                // swiftlint:disable:next force_unwrapping
                loadCompletion?.resume(throwing: error!)
                loadCompletion = nil
            }

            if let url = url {
                synchronizationQueue.sync {
                    for (key, predicate) in self.waitForURLPredicates where predicate(url) {
                        // invoke and finish.
                        if let unwrappedError = error {
                            self.waitForURLContinuations[key]?.resume(throwing: unwrappedError)
                        } else {
                            self.waitForURLContinuations[key]?.resume()
                        }

                        self.waitForURLPredicates.removeValue(forKey: key)
                        self.waitForURLContinuations.removeValue(forKey: key)
                        return
                    }
                }
            }
        }
    }

    class Delegate: NSObject, WKNavigationDelegate {
        private var loadPageSignal: LoadPageSignal

        init(_ loadPageSignal: LoadPageSignal) {
            self.loadPageSignal = loadPageSignal
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation) {
            loadPageSignal.signalURLLoadedResult(webView.url?.absoluteString)
        }

        func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation) {
            loadPageSignal.isPageLoaded = false
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation, withError error: Error) {
            loadPageSignal.signalURLLoadedResult(
                webView.url?.absoluteString,
                withError: PipeableError.navigationError(error.localizedDescription)
            )
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation, withError error: Error) {
            loadPageSignal.signalURLLoadedResult(
                webView.url?.absoluteString,
                withError: PipeableError.navigationError(error.localizedDescription)
            )
        }

        func webView(_: WKWebView, didReceive _: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadPageSignal.signalURLLoadedResult(
                webView.url?.absoluteString,
                withError: PipeableError.navigationError("Terminated")
            )
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

        init(_ frameInfoResolver: FrameInfoResolver) {
            self.frameInfoResolver = frameInfoResolver
        }

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
                    }
                }
            }
        }
    }

    public init(_ webView: WKWebView, _ frame: WKFrameInfo? = nil) {
        self.webView = webView
        self.frame = frame

        let config = webView.configuration

        var contents: String?

        let frameworkBundle = Bundle(for: PipeablePage.self)
        let pathInFramework = frameworkBundle.path(forResource: "sophia", ofType: "js")

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

        loadPageSignal = LoadPageSignal()

        // This is the main frame / page.
        if frame == nil {
            delegate = Delegate(loadPageSignal)
            self.webView.navigationDelegate = delegate
            self.webView.configuration.userContentController.add(ContentController(frameInfoResolver), name: "handler")
        }
    }

    deinit {
        if frame == nil {
            self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "handler")
        }
    }

    public func goto(_ url: String) async throws {
        print("page goto \(url)")

        loadPageSignal.isPageLoaded = false

        if let urlObj = URL(string: url) {
            let request = URLRequest(url: urlObj, timeoutInterval: 3)

            DispatchQueue.main.async {
                self.webView.load(request)
            }
        } else {
            throw PipeableError.navigationError("Incorrect URL \(url)")
        }

        try await waitForPageLoad()
    }

    public func reload() async throws {
        loadPageSignal.isPageLoaded = false
        await webView.reload()
        return try await waitForPageLoad()
    }

    // The async function you'll await
    public func waitForPageLoad() async throws {
        if frame != nil {
            // Iframes are already loaded, if we can address them.
            return
        }

        if loadPageSignal.isPageLoaded {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            self.loadPageSignal.loadCompletion = continuation
        }
    }

    public func waitForURL(_ predicate: @escaping (String) -> Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.loadPageSignal.addWaitForURL(predicate, continuation: continuation)
        }
    }

    public func querySelector(_ selector: String) async throws -> PipeableElement? {
        try await waitForPageLoad()

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
        try await waitForPageLoad()

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
        try await waitForPageLoad()

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

    public func waitForXPath(_ xpath: String, timeout: Int = 30000, visible _: Bool = false) async throws -> PipeableElement? {
        try await waitForPageLoad()

        print("Wait for XPath \(xpath) got past waitForPageLoad")

        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForXPath(xpath, opts);
            """,
            arguments: [
                "xpath": xpath,
                "opts": [
                    "timeout": String(timeout),
                    "visible": true
                ] as [String: Any]
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
        try await waitForPageLoad()

        let result = try await webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForSelector(selector, opts);
            """,
            arguments: [
                "selector": selector,
                "opts": [
                    "timeout": String(timeout),
                    "visible": visible
                ] as [String: Any]
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
        try await waitForPageLoad()

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

    public func evaluate(_ javascript: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            javascript,
            arguments: [:],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        // FIX THIS BIG TIME :)
        if let strResult = result as? String {
            return strResult
        } else {
            return ""
        }
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
    case initializationError
}

public class PipeableElement {
    var page: PipeablePage
    let elementId: String

    init(_ page: PipeablePage, _ elementId: String) {
        self.page = page
        self.elementId = elementId
    }

    public func click() async throws {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.click(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        print(result ?? "No result")
    }

    public func type(_ text: String, _ delay: Int = 10) async throws {
        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.type(elementHash, text, opts);
            """,
            arguments: [
                "elementHash": elementId,
                "text": text,
                "opts": [
                    "delay": delay
                ]
            ],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
    }

    public func focus() async throws {
        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.focus(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
    }

    // TODO: this should be frame, not page here I thinks -- we need to separate those. Maybe Page extends frame -- yes!
    public func contentFrame() async throws -> PipeablePage? {
        let requestId = randomString(length: 10)
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.sendFrameIDMessage(elementHash, requestId);
            """,
            arguments: ["elementHash": elementId, "requestId": requestId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        // TODO: Handle errors properly here....
        if let success = result as? Bool {
            if success {
                return try await withCheckedThrowingContinuation { continuation in
                    self.page.frameInfoResolver.synchronizationQueue.sync {
                        if let frameInfo = self.page.frameInfoResolver.frameInfos[requestId] {
                            self.page.frameInfoResolver.frameInfos.removeValue(forKey: requestId)
                            let resultPage = PipeablePage(self.page.webView, frameInfo)
                            continuation.resume(returning: resultPage)
                        } else {
                            self.page.frameInfoResolver.continuations[requestId] = continuation
                        }
                    }
                }
            } else {
                return nil
            }
        }

        return nil
    }

    public func textContent() async throws -> String? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.textContent(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        return result as? String
    }

    public func getAttribute(_ attributeName: String) async throws -> String? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.getAttribute(elementHash, attributeName);
            """,
            arguments: ["elementHash": elementId, "attributeName": attributeName],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        return result as? String
    }

    public func querySelector(_ selector: String) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$(selector, parentHash);
            """,
            arguments: ["selector": selector, "parentHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }

    public func querySelectorAll(_ selector: String) async throws -> [PipeableElement] {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$$(selector, parentHash);
            """,
            arguments: ["selector": selector, "parentHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self.page, elementId)
            }
        }

        return []
    }

    public func waitForSelector(_ selector: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForSelector(selector, opts);
            """,
            arguments: [
                "selector": selector,
                "opts": [
                    "parentElementHash": elementId,
                    "timeout": String(timeout),
                    "visible": visible
                ] as [String: Any]
            ],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }

    public func xpathSelector(_ xpath: String) async throws -> [PipeableElement] {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.$x(xpath, parentHash);
            """,
            arguments: ["xpath": xpath, "parentHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
        print(result ?? "No result")

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self.page, elementId)
            }
        }

        return []
    }

    public func waitForXPath(_ xpath: String, timeout: Int = 30000, visible _: Bool = false) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.SophiaJS.waitForXPath(xpath, opts);
            """,
            arguments: [
                "xpath": xpath,
                "opts": [
                    "timeout": String(timeout),
                    "visible": true,
                    "parentElementHash": elementId
                ] as [String: Any]
            ],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }
}

func randomString(length: Int) -> String {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    // swiftlint:disable:next force_unwrapping
    return String((0 ..< length).map { _ in characters.randomElement()! })
}
