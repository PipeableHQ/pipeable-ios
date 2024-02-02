@testable import PipeableSDK
import WebKit
import XCTest

final class PageScriptGotoTests: PipeableXCTestCase {
    func testGotoWithAboutBlank() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("about:blank");
            return page.url();
            """,
            page)

        // TODO: How do we handle return values from scripts?!?
        // swiftlint:disable:next force_cast
        let url = result.toObject() as! URL
        XCTAssertEqual(url.absoluteString, "about:blank")
    }

    func testGotoWithBadUrl() async throws {
        let page = PipeablePage(webView)

        do {
            _ = try await runScript(
                """
                await page.goto("blank");
                """,
                page)
            XCTFail("Expected an error, but no error was thrown.")
        } catch {
            // TODO: Should we map back to PipeableError in the scripts?!?
            if case ScriptError.error = error {
                return
            } else {
                XCTFail("Expected ScriptError.error, but got a different error: \(error)")
            }
        }
    }
}
