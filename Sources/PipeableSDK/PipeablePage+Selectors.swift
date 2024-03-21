import Foundation
import WebKit

public extension PipeablePage {
    /// Queries a single element matching a CSS selector.
    /// - Parameter selector: The CSS selector to match.
    /// - Returns: A `PipeableElement` representing the matched element, or `nil` if no match is found.
    /// - Throws: An error if JavaScript evaluation fails, e.g. a bad selector
    func querySelector(_ selector: String) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$(selector);
            """,
            arguments: ["selector": selector],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }

    /// Queries all elements matching a CSS selector.
    /// - Parameter selector: The CSS selector to match.
    /// - Returns: An array of `PipeableElement` objects representing the matched elements.
    /// - Throws: An error if JavaScript evaluation fails, e.g. a bad selector.
    func querySelectorAll(_ selector: String) async throws -> [PipeableElement] {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$$(selector);
            """,
            arguments: ["selector": selector],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self, elementId)
            }
        }

        return []
    }

    /// Queries the web page for all elements that match a specified XPath expression.
    /// - Parameter xpath: A string representing the XPath expression to evaluate against the elements in the page.
    /// - Returns: An array of `PipeableElement` objects representing all matching elements in the DOM.
    ///   Returns an empty array if no matching elements are found.
    /// - Throws: An error if the JavaScript evaluation fails, such as from an invalid XPath expression.
    func xpathSelector(_ xpath: String) async throws -> [PipeableElement] {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$x(xpath);
            """,
            arguments: ["xpath": xpath],
            in: frame,
            contentWorld: WKContentWorld.page
        )

        if let elementIds = result as? [String] {
            return elementIds.map { (elementId: String) -> PipeableElement in
                PipeableElement(self, elementId)
            }
        }

        return []
    }

    /// Waits for an element matching a specified XPath expression to appear in the web page.
    /// - Parameters:
    ///   - xpath: A string representing the XPath expression to wait for.
    ///   - timeout: The maximum time, in milliseconds, to wait for the element to appear. Defaults to 30000ms.
    ///   - visible: A Boolean indicating whether the element should be visible. Defaults to `false`.
    /// - Returns: An optional `PipeableElement` representing the matching element once it appears.
    ///   Returns `nil` if the element does not appear within the specified timeout period.
    /// - Throws: An error if the JavaScript evaluation fails or the wait operation times out.
    func waitForXPath(_ xpath: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForXPath(xpath, opts);
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

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }

    /// Waits for an element matching a specified CSS selector to appear in the web page.
    /// - Parameters:
    ///   - selector: A string representing the CSS selector to wait for.
    ///   - timeout: The maximum time, in milliseconds, to wait for the element to appear. Defaults to 30000ms.
    ///   - visible: A Boolean indicating whether the element should be visible. Defaults to `false`.
    /// - Returns: An optional `PipeableElement` representing the matching element once it appears.
    ///   Returns `nil` if the element does not appear within the specified timeout period.
    /// - Throws: An error if the JavaScript evaluation fails or the wait operation times out.
    func waitForSelector(_ selector: String, timeout: Int = 30000, visible: Bool = false) async throws -> PipeableElement? {
        let result = try await webView.callAsyncJavaScript(
            """
                return window.PipeableJS.waitForSelector(selector, opts);
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

        if let elementId = result as? String {
            return PipeableElement(self, elementId)
        }

        return nil
    }
}
