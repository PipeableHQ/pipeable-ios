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
            page
        )

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
                page
            )
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

    func testGotoWithTimeoutFail() async throws {
        let page = PipeablePage(webView)
        do {
            _ = try await runScript(
                """
                await page.goto("\(testServerURL)/goto/timeout/3000", { timeout: 1_000 });
                """,
                page
            )

            XCTFail("Expected an error, but no error was thrown.")
        } catch {
            // Check if the caught error is of type PipeableError.navigationError ("The request timed out.")
            if case let ScriptError.error(reason) = error {
                if reason.contains("timed out") {
                    return
                }
            }

            // If the error is not of the expected type, fail the test
            XCTFail("Expected ScriptError.error with timeout, but got a different error: \(error)")
        }
    }

    func testGotoWithTimeoutSuccess() async throws {
        let page = PipeablePage(webView)
        _ = try await runScript(
            """
            await page.goto("\(testServerURL)/goto/timeout/0", { timeout: 2_000 });
            """,
            page
        )
    }
}
