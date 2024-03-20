import Foundation
import WebKit

public extension PipeablePage {
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
