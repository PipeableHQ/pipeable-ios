@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageSubmitActiveFormTests: PipeableXCTestCase {
    func testSubmitSimpleForm() async throws {
        let page = PipeablePage(webView)

        let resp = try? await page.goto("\(testServerURL)/forms/simple_form.html")
        XCTAssertEqual(resp?.status, 200)

        let inputEl = try await page.querySelector("input[name='q']")
        try await inputEl?.type("hello")

        let formSubmitted = try await page.submitActiveForm()
        XCTAssertEqual(formSubmitted, true)

        let formSubmittedResult = try await page.evaluate("window.formSubmitted")

        XCTAssertEqual(formSubmittedResult as? Bool, true)
    }

    func testSubmitAndNavigate() async throws {
        let page = PipeablePage(webView)

        let resp = try? await page.goto("\(testServerURL)/forms/form_with_get_submission.html")
        XCTAssertEqual(resp?.status, 200)

        let inputEl = try await page.querySelector("input[name='q']")
        try await inputEl?.type("hello")

        let formSubmitted = try await page.submitActiveForm()
        XCTAssertEqual(formSubmitted, true)

        try await page.waitForURL { url in url.contains("q=hello") }

        let url = await page.url()
        XCTAssertEqual(url?.absoluteString, "\(testServerURL)/forms/form_with_get_submission.html?q=hello")
    }

    func testSubmitActiveFormWhenThereIsNoForm() async throws {
        let page = PipeablePage(webView)

        let resp = try await page.goto("\(testServerURL)/querySelector/simple.html")
        XCTAssertEqual(resp?.status, 200)

        let formSubmitted = try await page.submitActiveForm()
        XCTAssertEqual(formSubmitted, false)
    }

    func testSubmitActiveWhenNoFormIsActive() async throws {
        let page = PipeablePage(webView)

        let resp = try? await page.goto("\(testServerURL)/forms/form_with_get_submission.html")
        XCTAssertEqual(resp?.status, 200)

        let formSubmitted = try await page.submitActiveForm()
        XCTAssertEqual(formSubmitted, false)
    }
}
