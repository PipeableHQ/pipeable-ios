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
    
    func testPropagation() async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("\(testServerURL)/click.html")

        let clicksBefore = try await page.evaluate("window.clicksOuter")
        guard let numClicksBefore = clicksBefore as? Int else {
            XCTFail("Could not read clicks")
            return
        }
        let focusesBefore = try await page.evaluate("window.focusesOuter")
        guard let numFocusesBefore = focusesBefore as? Int else {
            XCTFail("Could not read focuses")
            return
        }
        let focusesInBefore = try await page.evaluate("window.focusesInOuter")
        guard let numFocusesInBefore = focusesInBefore as? Int else {
            XCTFail("Could not read focuses")
            return
        }

        let outerContainerEl = try await page.querySelector("#outer_container")
        try await outerContainerEl?.click()

        let clicksAfter = try await page.evaluate("window.clicksOuter")
        guard let numClicksAfter = clicksAfter as? Int else {
            XCTFail("Could not read clicks")
            return
        }
        let focusesAfter = try await page.evaluate("window.focusesOuter")
        guard let numFocusesAfter = focusesAfter as? Int else {
            XCTFail("Could not read focuses")
            return
        }
        let focusesInAfter = try await page.evaluate("window.focusesInOuter")
        guard let numFocusesInAfter = focusesInAfter as? Int else {
            XCTFail("Could not read focusesIn")
            return
        }

        XCTAssertEqual(numFocusesAfter, numFocusesBefore, "Focus should not bubble")
        XCTAssertEqual(numFocusesInAfter, numFocusesInBefore + 1, "FocusIn not registered")
        XCTAssertEqual(numClicksAfter, numClicksBefore + 1, "Click not registered")
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
        let focusesBefore = try await page.evaluate("window.focuses")
        guard let numFocusesBefore = focusesBefore as? Int else {
            XCTFail("Could not read focuses")
            return
        }
        let focusesInBefore = try await page.evaluate("window.focusesIn")
        guard let numFocusesInBefore = focusesInBefore as? Int else {
            XCTFail("Could not read focuses")
            return
        }

        try await action(page)

        let clicksAfter = try await page.evaluate("window.clicks")
        guard let numClicksAfter = clicksAfter as? Int else {
            XCTFail("Could not read clicks")
            return
        }
        let focusesAfter = try await page.evaluate("window.focuses")
        guard let numFocusesAfter = focusesAfter as? Int else {
            XCTFail("Could not read focuses")
            return
        }
        let focusesInAfter = try await page.evaluate("window.focusesIn")
        guard let numFocusesInAfter = focusesInAfter as? Int else {
            XCTFail("Could not read focusesIn")
            return
        }

        XCTAssertEqual(numFocusesAfter, numFocusesBefore + 1, "Focus not registered")
        XCTAssertEqual(numFocusesInAfter, numFocusesInBefore + 1, "FocusIn not registered")
        XCTAssertEqual(numClicksAfter, numClicksBefore + 1, "Click not registered")
    }
}
