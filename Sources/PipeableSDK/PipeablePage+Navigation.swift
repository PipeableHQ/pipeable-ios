import Foundation
import WebKit

public extension PipeablePage {
    /// Enum representing the various states to wait for before considering a navigation or page action complete.
    ///
    /// - `load`: Wait until the `load` event is fired, indicating that the entire page and all dependent resources have loaded.
    /// - `domcontentloaded`: Wait until the `DOMContentLoaded` event is fired, indicating that the HTML is fully parsed,
    /// but stylesheets, images, and subframes may still be loading.
    /// - `networkidle`: Wait until the network is idle, meaning there are no ongoing network requests for a specified time period (0.5s).
    /// This state implies that most, if not all, resources have been fetched and processed.
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

    /// Navigates the web view to a specified URL.
    /// - Parameters:
    ///   - url: The URL to navigate to.
    ///   - waitUntil: Specifies the event to wait for before considering the navigation complete. Defaults to `.load`.
    ///                Other options are `.domcontentloaded` and `.networkidle.`
    ///   - timeout: The maximum time in milliseconds to wait for the navigation to complete. Defaults to 30000ms.
    /// - Returns: A `PipeableHTTPResponse` object representing the HTTP response, or `nil` if the response is not available.
    /// - Throws: `PipeableError.navigationError` if navigation fails.
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

    /// Reloads the current page.
    /// - Parameters:
    ///   - waitUntil: Specifies the event to wait for before considering the reload complete. Defaults to `.load`.
    ///   - timeout: The maximum time in milliseconds to wait for the reload to complete. Defaults to 30000ms.
    /// - Throws: `PipeableError.navigationError` if reload fails.
    func reload(waitUntil: WaitUntilOption = .load, timeout: Int = 30000) async throws {
        pageLoadState.changeState(state: .notloaded, url: nil)
        await webView.reload()
        return try await waitForLoadState(waitUntil: waitUntil, timeout: timeout)
    }

    /// Waits for a specified load state.
    /// - Parameters:
    ///   - waitUntil: The load state to wait for.
    ///   - timeout: The maximum time in milliseconds to wait. Defaults to 30000ms.
    /// - Throws: An error if the wait condition is not met within the timeout.
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

    /// Waits for an asynchornous request made via XMLHttpRequest (XHR) or fetch to complete that matches the specified URL.
    /// - Parameters:
    ///   - url: Partial URL of the request to wait for.
    ///   - timeout: The maximum time, in milliseconds, to wait for the XHR request to complete. Defaults to 30000ms (30 seconds).
    ///
    /// - Returns: An optional `XHRResult` object containing details about the completed XHR request, including
    ///   status code, response body, response headers, the request URL, and the response type. Returns `nil` if the request
    ///   does not complete within the specified timeout or if the response cannot be properly decoded.
    ///
    /// - Throws: `PipeableError.invalidResponse` if the function fails to decode the XHR response or if the JavaScript
    ///   execution returns an unexpected result. This error indicates an issue with the response format or a failure
    ///   in the underlying JavaScript execution mechanism.
    func waitForResponse(_ url: String, timeout: Int = 30000) async throws -> XHRResult? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForResponse(url, timeout);
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

/// Represents the HTTP response received from navigating to a URL or making an HTTP request.
/// This structure is used to capture and provide details about the HTTP response, including
/// the status code and headers.
public struct PipeableHTTPResponse: Decodable {
    /// The HTTP status code of the response.
    public var status: Int

    /// A dictionary containing the HTTP headers of the response. The keys are header field names,
    /// and the values are the corresponding header field values.
    public var headers: [String: String]
}

/// Represents the result of an asynchronous request XMLHttpRequest (XHR) captured.
/// It provides detailed information about the XHR request and its response.
public struct XHRResult: Decodable {
    /// Enumerates the possible types of responses that an XHR request can produce,
    /// matching the JavaScript XHR API response types.
    public enum ResponseType: String, Decodable {
        case none = ""
        case text
        case arraybuffer
        case blob
        case document
        case json
    }

    /// The HTTP status code of the XHR response.
    public var status: Int

    /// The body of the XHR response, represented as a String. The actual format of this
    /// string depends on the `responseType`.
    public var body: String

    /// A string representing the headers of the XHR response. This string could be
    /// parsed further to extract individual header values.
    public var headers: String

    /// The URL to which the XHR request was made.
    public var url: String

    /// The type of the response, indicating how the response body is interpreted
    /// and what format it is in.
    public var responseType: ResponseType
}
