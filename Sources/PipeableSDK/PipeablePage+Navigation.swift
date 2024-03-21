import Foundation
import WebKit

public extension PipeablePage {
    enum WaitUntilOption: String {
        case load
        case domcontentloaded
        case networkidle
    }

    internal actor LastHTTPResponse {
        var lastHTTPResponse: PipeableHTTPResponse?

        func setLastHTTPResponse(_ response: PipeableHTTPResponse?) {
            lastHTTPResponse = response
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

    func goto(_ url: String, waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws -> PipeableHTTPResponse? {
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

    func reload(waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
        pageLoadState.changeState(state: .notloaded, url: nil)
        await webView.reload()
        return try await waitForLoadState(waitUntil: waitUntil, timeout: timeout)
    }

    func waitForLoadState(waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
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

    /// Waits for the WebView to navigate to a URL that matches the given predicate.
    /// - Parameters:
    /// - predicate: A closure that takes a URL and returns a boolean.
    /// - waitUntil: When to consider navigation as finished, defaults to `.load`.
    /// - timeout: Maximum time to wait for the navigation to finish, defaults to 30000ms.
    /// - ignoreNavigationErrors: If true, ignores navigation errors and waits for the URL to match the predicate.
    /// - Throws: PipeableError.navigationError if the navigation fails and ignoreNavigationErrors is false.
    func waitForURL(
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

    func waitForXHR(_ url: String, timeout: Int = 30000) async throws -> XHRResult? {
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
