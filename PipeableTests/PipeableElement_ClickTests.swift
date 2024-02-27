@testable import PipeableSDK
import WebKit
import XCTest

final class PipeableElementClickTests: PipeableXCTestCase {
    func testNormalElementClick() async throws {
        try await registerClick { page in
            let normalClickEl = try await page.querySelector("#normal_link")
            try await normalClickEl?.click()
        }
    }

    func testInlineLinkClick() async throws {
        try await registerClick { page in
            let inlineClickEl = try await page.querySelector("#normal_inlinejs_link")
            try await inlineClickEl?.click()
        }
    }

    func testClickOnOuterContainer() async throws {
        try await registerClick { page in
            let outerContainerEl = try await page.querySelector("#outer_container")
            try await outerContainerEl?.click()
        }
    }

    func testClickOnInvisibleElementsShouldFail() async throws {
        let page = PipeablePage(webView)
        _ = try? await page.goto("\(testServerURL)/click.html")
        let invisibleLinkEl = try await page.querySelector("#invisible_link")

        do {
            try await invisibleLinkEl?.click(timeout: 500)
            XCTFail("Should fail on invisible links with timeout")
        } catch {
            XCTAssert(String(describing: error).contains("Timed out waiting for element to become visible"))
        }
    }

    func testClickOnElementThatBecomesVisibleShouldWork() async throws {
        try await registerClick { page in
            let eventuallyVisibleEl = try await page.querySelector("#eventually_visible")
            try await eventuallyVisibleEl?.click()
        }
    }

    private func registerClick(action: @escaping (_ page: PipeablePage) async throws -> Void) async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("\(testServerURL)/click.html")

        let clicksBefore = try await page.evaluate("window.clicks")
        guard let numClicksBefore = clicksBefore as? Int else {
            XCTFail("Could not read clicks")
            return
        }

        try await action(page)

        let clicksAfter = try await page.evaluate("window.clicks")
        guard let numClicksAfter = clicksAfter as? Int else {
            XCTFail("Could not read clicks")
            return
        }

        XCTAssertEqual(numClicksAfter, numClicksBefore + 1, "Click not registered")
    }
}
