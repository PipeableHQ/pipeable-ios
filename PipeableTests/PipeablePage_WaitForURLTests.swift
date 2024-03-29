@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageWaitForURLTests: PipeableXCTestCase {
    func testGotoWithAboutBlankAndWaitForURL() async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("about:blank")

        try await page.waitForURL { url in url == "about:blank" }

        let url = await page.url()
        XCTAssertEqual(url?.absoluteString, "about:blank")
    }

    func testWaitForURLSuccess() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
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

        _ = try await page.goto(
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

    func testWaitForURLProperlyHandlesNavigationErrors() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
            "\(testServerURL)/load_latency/0/index.html",
            waitUntil: .domcontentloaded
        )

        // Start asynchronously waiting for URL.
        // We will navigate to a non-existing page in the meantime
        // We will start two waitForURLs -- one that ignores navigation errors
        // and one that doesnt and confirm they exhibit the correct behavior.

        let waitForPredicate = { url in
            url == "\(testServerURL)/load_latency/0/another.html"
        }

        let waitForURLIgnoreError = Task {
            try await page.waitForURL(
                waitForPredicate,
                waitUntil: .domcontentloaded,
                ignoreNavigationErrors: true
            )
        }

        let waitForURLNoIgnore = Task {
            try await page.waitForURL(
                waitForPredicate,
                waitUntil: .domcontentloaded
            )
        }

        // Navigate to a non-existing page
        do {
            _ = try await page.goto(
                "http://localhost:3001/non-existing-page",
                waitUntil: .domcontentloaded
            )

            XCTFail("Should have received an error")
        } catch {
            // Good. The navigation errored out.
        }

        // Now navigate to the proper url.
        _ = try await page.goto("\(testServerURL)/load_latency/0/another.html")

        // Wait for the waitForURL to finish.
        do {
            try await waitForURLIgnoreError.value
        } catch {
            XCTFail("Unexpected error \(error)")
        }

        do {
            try await waitForURLNoIgnore.value
            XCTFail("Should have errored with a navigation error")
        } catch {
            if let error = error as? PipeableError {
                if case .navigationError(let reason) = error {
                    XCTAssertEqual(reason, "Could not connect to the server.")
                } else {
                    XCTFail("Unexpected error \(error)")
                }
            } else {
                XCTFail("Unexpected error \(error)")
            }
        }
    }
}
