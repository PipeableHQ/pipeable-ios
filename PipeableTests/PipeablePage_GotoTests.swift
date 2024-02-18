@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageGotoTests: PipeableXCTestCase {
    func testGotoWithAboutBlank() async throws {
        let page = PipeablePage(webView)

        try? await page.goto("about:blank")

        let url = await page.url()
        XCTAssertEqual(url?.absoluteString, "about:blank")
    }

    func testGotoWithBadUrl() async throws {
        let page = PipeablePage(webView)

        do {
            try await page.goto("blank")
            XCTFail("Expected an error, but no error was thrown.")
        } catch {
            // Check if the caught error is of type PipeableError.navigationError
            if case PipeableError.navigationError = error {
                // This means the error is of the expected type, and you can proceed with the test
                return
            } else {
                // If the error is not of the expected type, fail the test
                XCTFail("Expected PipeableError.navigationError, but got a different error: \(error)")
            }
        }
    }

    func testGotoWithTimeoutFail() async throws {
        let page = PipeablePage(webView)
        do {
            try await page.goto("http://localhost:3000/goto/timeout/5", waitUntil: .domcontentloaded, timeout: 1000)
            XCTFail("Expected an error, but no error was thrown.")
        } catch {
            // Check if the caught error is of type PipeableError.navigationError ("The request timed out.")
            if case PipeableError.navigationError = error {
                return
            } else {
                // If the error is not of the expected type, fail the test
                XCTFail("Expected PipeableError.navigationError, but got a different error: \(error)")
            }
        }
    }

    func testGotoWithTimeoutSuccess() async throws {
        let page = PipeablePage(webView)

        try await page.goto("http://localhost:3000/goto/timeout/0", waitUntil: .domcontentloaded, timeout: 2000)
    }

    func testGotoWithWaitUntilLoad() async throws {
        let page = PipeablePage(webView)

        try await page.goto("http://localhost:3000/goto/timeout/0", waitUntil: .load, timeout: 2000)
    }

    func testGotoWithWaitUntilLoadTimeoutFail() async throws {
        let page = PipeablePage(webView)

        do {
            try await page.goto("http://localhost:3000/load_latency/2/index.html", waitUntil: .load, timeout: 1000)
            XCTFail("Expected to timeout while waiting for load")
        } catch {
            // Check if the caught error is of type PipeableError.navigationError
            if case PipeableError.navigationError = error {
                // This means the error is of the expected type, and you can proceed with the test
                return
            } else {
                // If the error is not of the expected type, fail the test
                XCTFail("Expected PipeableError.navigationError, but got a different error: \(error)")
            }
        }

        // Wait 1 second to make sure the load event fires, so we can validate
        // that Pipeable doesn't crash with 2 resume continuations.
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec.
    }

    func testGotoDomcontentLoadedButNotLoad() async throws {
        let page = PipeablePage(webView)

        try await page.goto("http://localhost:3000/load_latency/2/index.html", waitUntil: .domcontentloaded, timeout: 1000)

        do {
            try await page.waitForLoadState(waitUntil: .load, timeout: 1000)
            XCTFail("Expected to timeout while waiting for load")
        } catch {
            // Check if the caught error is of type PipeableError.navigationError
            if case PipeableError.navigationError = error {
                // This means the error is of the expected type, and you can proceed with the test
                return
            } else {
                // If the error is not of the expected type, fail the test
                XCTFail("Expected PipeableError.navigationError, but got a different error: \(error)")
            }
        }
    }
}
