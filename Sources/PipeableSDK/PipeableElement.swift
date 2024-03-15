import WebKit

public class PipeableElement {
    private var page: PipeablePage
    let elementId: String

    init(_ page: PipeablePage, _ elementId: String) {
        self.page = page
        self.elementId = elementId
    }

    public func click(timeout: Int? = nil) async throws {
        let timeout = timeout ?? 30000

        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.click(elementHash, { timeout: timeout });
            """,
            arguments: ["elementHash": elementId, "timeout": timeout],
            in: page.frame,
            contentWorld: WKContentWorld.page
        )

        print(result ?? "No result")
    }

    public func type(_ text: String, _ delay: Int = 10) async throws {
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
    public func contentFrame() async throws -> PipeablePage? {
        let requestId = randomString(length: 10)
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
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }

    public func xpathSelector(_ xpath: String) async throws -> [PipeableElement] {
        let result = try await page.webView.callAsyncJavaScript(
            """
                return window.PipeableJS.$x(xpath, parentHash);
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
        print(result ?? "No result")

        if let elementId = result as? String {
            return PipeableElement(page, elementId)
        }

        return nil
    }
}
