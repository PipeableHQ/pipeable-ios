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

    struct WindowData {
        let clicks: Int
        let focuses: Int
        let focusesIn: Int
    }

    func getWindowData(_ page: PipeablePage, _ outer: Bool) async throws -> WindowData? {
        let suffix = outer ? "Outer" : ""
        let clicks = try await page.evaluate("window.clicks\(suffix)")
        guard let numClicks = clicks as? Int else {
            XCTFail("Could not read clicks")
            return nil
        }
        let focuses = try await page.evaluate("window.focuses\(suffix)")
        guard let numFocuses = focuses as? Int else {
            XCTFail("Could not read focuses")
            return nil
        }
        let focusesIn = try await page.evaluate("window.focusesIn\(suffix)")
        guard let numFocusesIn = focusesIn as? Int else {
            XCTFail("Could not read focusesin")
            return nil
        }
        return WindowData(clicks: numClicks, focuses: numFocuses, focusesIn: numFocusesIn)
    }

    func testClickAndFocusLaunchFromSameElement() async throws {
        // 1) We "click" on the `outer_container` using Pipeable, but the way the click logic is implemented we find the innermost element (the link) and emit the click from there.
        // 2) Because we are emitting the click from the innermost element (the link), there is a question about where we should emit the focus event, should it be on the innermost element that we launched the click event from or should it be on the `outer_container` that we referenced when we did the initial click. Right now we emit the focus event from the innermost element along with the click, and this is identical to the behavior of playwright (atleast for this specific test).
        // 3) Since we are emitting the click and the focus events from the innermost element (even though we are clicking on `outer_container`), and focus events do not bubble (but focusin and clicks do) we expect a focus event on the link and no `focus` event on the `outer_container`.

        let page = PipeablePage(webView)
        _ = try? await page.goto("\(testServerURL)/click.html")

        guard let before = try await getWindowData(page, true) else {
            XCTFail("Could not read window data")
            return
        }

        let outerContainerEl = try await page.querySelector("#outer_container")
        try await outerContainerEl?.click()

        guard let after = try await getWindowData(page, true) else {
            XCTFail("Could not read window data")
            return
        }

        XCTAssertEqual(after.focuses, before.focuses, "Focus does not bubble")
        XCTAssertEqual(after.focusesIn, before.focusesIn + 1, "Focus in not registered")
        XCTAssertEqual(after.clicks, before.clicks + 1, "Click not registered")
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

    func testClickThenOnBlur() async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("\(testServerURL)/click.html")

        let onBlursBefore = try await page.evaluate("window.onBlurs")
        guard let numOnBlursBefore = onBlursBefore as? Int else {
            XCTFail("Could not read on blurs")
            return
        }

        // type some text
        let textInEl = try await page.querySelector("#text_input")
        try await textInEl?.focus()
        try await textInEl?.type("hello")

        // click on another element to make sure onblur is fired for our text input
        let linkEl = try await page.querySelector("#normal_link")
        try await linkEl?.click()

        let onBlursAfter = try await page.evaluate("window.onBlurs")
        guard let numOnBlursAfter = onBlursAfter as? Int else {
            XCTFail("Could not read on blurs")
            return
        }

        XCTAssertEqual(numOnBlursAfter, numOnBlursBefore + 1, "Blur not registered")
    }

    func testClickOnContainerWithDisabledElementInside() async throws {
        // Clicking on a container with a disabled element inside the container,
        // this currently almost matches Playwright except that we
        // also record a click on the disabled element (and playwright does not).
        // Because we are using the built in method to emit focus events
        // for HTMLElement the focus behavior matches Playwright.
        let page = PipeablePage(webView)

        _ = try? await page.goto("\(testServerURL)/click.html")

        guard let before = try await getWindowData(page, false) else {
            XCTFail("Could not read window data")
            return
        }
        guard let beforeOuter = try await getWindowData(page, true) else {
            XCTFail("Could not read window data")
            return
        }

        let disabledEl = try await page.querySelector("#disabled_element")
        try await disabledEl?.click()

        guard let after = try await getWindowData(page, false) else {
            XCTFail("Could not read window data")
            return
        }
        guard let afterOuter = try await getWindowData(page, true) else {
            XCTFail("Could not read window data")
            return
        }

        XCTAssertEqual(after.focuses, before.focuses, "Extra focus registered")
        XCTAssertEqual(after.focusesIn, before.focusesIn, "Extra focusin registered")
        XCTAssertEqual(after.clicks, before.clicks + 1, "Click not registered")


        XCTAssertEqual(afterOuter.focuses, beforeOuter.focuses, "Extra focus registered")
        XCTAssertEqual(afterOuter.focusesIn, beforeOuter.focusesIn, "Extra focusin registered")
        XCTAssertEqual(afterOuter.clicks, beforeOuter.clicks + 1, "Click not registered")
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
            XCTFail("Could not read focuses in")
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
            XCTFail("Could not read focuses in")
            return
        }

        XCTAssertEqual(numFocusesAfter, numFocusesBefore + 1, "Focus not registered")
        XCTAssertEqual(numFocusesInAfter, numFocusesInBefore + 1, "Focus in not registered")
        XCTAssertEqual(numClicksAfter, numClicksBefore + 1, "Click not registered")
    }
}
