@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageGotoTests: PipeableXCTestCase {
    func testGotoWithAboutBlank() async throws {
        let page = PipeablePage(webView)

        try? await page.goto("about:blank")

        let url = page.url()
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
}
