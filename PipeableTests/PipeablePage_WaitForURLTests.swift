@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageWaitForURLTests: PipeableXCTestCase {
    func testGotoWithAboutBlankAndWaitForURL() async throws {
        let page = PipeablePage(webView)

        try? await page.goto("about:blank")

        try await page.waitForURL { url in url == "about:blank" }

        let url = await page.url()
        XCTAssertEqual(url?.absoluteString, "about:blank")
    }

    func testWaitForURLSuccess() async throws {
        let page = PipeablePage(webView)

        try await page.goto(
            "\(testServerURL)/load_latency/3000/index.html",
            waitUntil: .domcontentloaded
        )

        guard let linkEl = try await page.waitForSelector("a#link_to_another") else {
            XCTFail("Could not find the link element")
            return
        }

        try await linkEl.click()

        let waitForPredicate = { url in
            url == "\(testServerURL)/load_latency/3000/another.html"
        }

        try await page.waitForURL(waitForPredicate, waitUntil: .domcontentloaded, timeout: 1000)

        let h1El = try await page.waitForSelector("h1")
        let text = try await h1El?.textContent()
        XCTAssertEqual(text, "Hello from another!")
    }

    func testWaitForURLWithTimeout() async throws {
        let page = PipeablePage(webView)

        try await page.goto(
            "\(testServerURL)/load_latency/2000/index.html",
            waitUntil: .domcontentloaded
        )

        guard let linkEl = try await page.waitForSelector("a#link_to_another") else {
            XCTFail("Could not find the link element")
            return
        }

        try await linkEl.click()

        let waitForPredicate = { url in
            url == "\(testServerURL)/load_latency/2000/another.html"
        }

        do {
            try await page.waitForURL(waitForPredicate, waitUntil: .load, timeout: 500)
        } catch {
            if let error = error as? PipeableError {
                if case .navigationError = error {
                    return
                }
            }

            XCTFail("Unexpected error \(error)")
        }

        XCTFail("Should have timed out")
    }
}
