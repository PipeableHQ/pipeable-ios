@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageAddUserScriptTests: PipeableXCTestCase {
    func testAddUserScriptAtDocumentStartBeforeLoad() async throws {
        let page = PipeablePage(webView)

        page.addUserScript("window.myVar = 5")

        _ = try? await page.goto("about:blank")

        let myVarVal = try await page.evaluate("window.myVar")

        XCTAssertEqual(myVarVal as? Int, 5)
    }

    func testAddUserScriptAtDocumentEndAfterLoad() async throws {
        let page = PipeablePage(webView)
        page.addUserScript(
            "window.divsAtStart = document.querySelectorAll('div').length",
            injectionTime: .atDocumentStart
        )
        page.addUserScript(
            "window.divsAtEnd = document.querySelectorAll('div').length",
            injectionTime: .atDocumentEnd
        )

        _ = try? await page.goto("\(testServerURL)/load_latency/0/index.html")

        let divsAtStart = try await page.evaluate("window.divsAtStart")
        let divsAtEnd = try await page.evaluate("window.divsAtEnd")

        let divsNow = try await page.evaluate("document.querySelectorAll('div').length")

        XCTAssertEqual(divsAtStart as? Int, 0)
        XCTAssertEqual(divsAtEnd as? Int, divsNow as? Int)
        XCTAssertGreaterThan(divsNow as? Int ?? 0, 0)
    }
}
