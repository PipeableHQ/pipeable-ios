import WebKit

/// `PipeableElement` represents a single element within a web page, accessible through a `PipeablePage` instance.
/// It encapsulates the functionality to interact with and manipulate web elements within the context of a `WKWebView`.
///
/// Instances of `PipeableElement` are typically obtained through various query methods provided by `PipeablePage`,
/// such as `querySelector`, `querySelectorAll`, `xpathSelector`, etc. These methods allow you to locate elements
/// within the web page's DOM based on CSS selectors or XPath expressions.
///
/// Once obtained, a `PipeableElement` can be used to perform a variety of actions on the corresponding web element,
/// including clicking, typing text, focusing, blurring, and retrieving attributes or text content. It also provides
/// methods to wait for and query further elements within its context, enabling detailed interaction and navigation
/// within web pages.
public class PipeableElement {
    private var page: PipeablePage
    let elementId: String

    init(_ page: PipeablePage, _ elementId: String) {
        self.page = page
        self.elementId = elementId
    }

    /// Clicks the element.
    /// Waits for the element to become visible, hovers it and clicks it.
    /// The click event is triggered in the innermost child of this element and propagated up.
    /// - Parameter timeout: The maximum time in milliseconds to wait for the click action to complete. Defaults to 30000ms.
    /// - Throws: An error if the click action fails.
    public func click(timeout: Int? = nil) async throws {
        let timeout = timeout ?? 30000

        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.click(elementHash, { timeout: timeout });
            """,
            arguments: ["elementHash": elementId, "timeout": timeout],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
    }

    /// Types text into the element.
    /// - Parameters:
    ///   - text: The text to type into the element.
    ///   - delay: The delay between key presses in milliseconds. Defaults to 10ms.
    /// - Throws: An error if typing fails.
    public func type(_ text: String, delay: Int = 10) async throws {
        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.type(elementHash, text, opts);
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

    /// Sets focus on the element.
    /// - Throws: An error if the element has been removed from the dom
    public func focus() async throws {
        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.focus(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
    }

    /// Removes focus from the element.
    public func blur() async throws {
        _ = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.blur(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )
    }

    // TODO: this should be frame, not page here I thinks -- we need to separate those. Maybe Page extends frame -- yes!
    /// Gets the content frame for an iframe/frame element, if it exists.
    /// - Returns: A `PipeablePage` representing the content frame, or `nil` if the element does not have a content frame.
    /// - Throws: An error if fetching the content frame fails.
    public func contentFrame() async throws -> PipeablePage? {
        let requestId = UUID().uuidString
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.sendFrameIDMessage(elementHash, requestId);
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

    /// Retrieves the text content of the element.
    /// - Returns: The text content of the element, or `nil` if it cannot be retrieved.
    /// - Throws: An error if fetching the text content fails.
    public func textContent() async throws -> String? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.textContent(elementHash);
            """,
            arguments: ["elementHash": elementId],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        return result as? String
    }

    /// Gets the value of a specified attribute of the element.
    /// - Parameter attributeName: The name of the attribute to retrieve.
    /// - Returns: The value of the attribute, or `nil` if the attribute does not exist.
    /// - Throws: An error if fetching the attribute fails.
    public func getAttribute(_ attributeName: String) async throws -> String? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.getAttribute(elementHash, attributeName);
            """,
            arguments: ["elementHash": elementId, "attributeName": attributeName],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        return result as? String
    }

    /// Queries a single descendant element that matches a given CSS selector.
    /// - Parameter selector: The CSS selector to match.
    /// - Returns: A `PipeableElement` representing the matched descendant, or `nil` if no match is found.
    /// - Throws: An error if the query fails.
    public func querySelector(_ selector: String) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$(selector, parentHash);
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

    /// Queries all descendant elements that match a given CSS selector.
    /// - Parameter selector: The CSS selector to match.
    /// - Returns: An array of `PipeableElement` objects representing the matched descendants.
    /// - Throws: An error if the query fails.
    public func querySelectorAll(_ selector: String) async throws -> [PipeableElement] {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$$(selector, parentHash);
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

    /// Waits for a descendant element to appear that matches a given CSS selector.
    /// - Parameters:
    ///   - selector: The CSS selector to wait for.
    ///   - timeout: The maximum time in milliseconds to wait. Defaults to 30000ms.
    ///   - visible: If `true`, waits for the element to become visible. Defaults to `false`.
    /// - Returns: A `PipeableElement` representing the matched descendant, or `nil` if the wait times out.
    /// - Throws: An error if the wait fails.
    public func waitForSelector(_ selector: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForSelector(selector, opts);
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

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }

    /// Queries the web page for all elements that match a specified XPath expression, relative to the current element.
    /// - Parameter xpath: A string representing the XPath expression to evaluate against the elements within the current
    ///   element's context.
    /// - Returns: An array of `PipeableElement` objects representing all matching elements found. Returns an empty array
    ///   if no matching elements are discovered.
    /// - Throws: An error if the JavaScript evaluation fails, such as from an invalid XPath expression.
    public func xpathSelector(_ xpath: String) async throws -> [PipeableElement] {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$x(xpath, parentHash);
            """,
            arguments: ["xpath": xpath, "parentHash": elementId],
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

    /// Waits for an element matching a specified XPath expression to appear within the current element's context in the web page.
    /// - Parameters:
    ///   - xpath: A string representing the XPath expression to wait for.
    ///   - timeout: The maximum time, in milliseconds, to wait for the element to appear. Defaults to 30000ms (30 seconds).
    ///   - visible: A Boolean indicating whether the element should be visible upon being found. Defaults to `false`.
    /// - Returns: An optional `PipeableElement` representing the matching element once it appears within the current element's
    ///   context. Returns `nil` if the element does not appear within the specified timeout period.
    /// - Throws: An error if the JavaScript evaluation fails or the wait operation times out before finding a match.
    public func waitForXPath(_ xpath: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForXPath(xpath, opts);
            """,
            arguments: [
                "xpath": xpath,
                "opts": [
                    "timeout": String(timeout),
                    "visible": visible,
                    "parentElementHash": elementId
                ] as [String: Any]
            ],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }
}
