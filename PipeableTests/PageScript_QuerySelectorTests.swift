@testable import PipeableSDK
import WebKit
import XCTest

final class PageScriptQuerySelectorTests: PipeableXCTestCase {
    func testQuerySelectorSuccess() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("\(testServerURL)/querySelector/simple.html");

            const selectById = await page.querySelector('#specialItem');
            const textContent = await selectById.textContent();

            const text = await selectById?.textContent();
            return text;
            """, page)

        XCTAssertEqual(result.toString(), "Special Item")
    }

    func testQuerySelectorInvalidSelector() async throws {
        let page = PipeablePage(webView)
        do {
            _ = try await runScript(
                """
                await page.goto("\(testServerURL)/querySelector/simple.html");

                const selectById = await page.querySelector('this[1]isnt[v]valid');
                const textContent = await selectById.textContent();

                const text = await selectById?.textContent();
                return text;
                """, page)

            XCTFail("Should fail with SyntaxError")
        } catch let ScriptError.error(reason) {
            XCTAssert(reason.contains("SyntaxError"), "Did not receive SyntaxError: \(reason)")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testQuerySelectorNoResults() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("\(testServerURL)/querySelector/simple.html");

            const selectById = await page.querySelector('div.crazyClass');
            return !!selectById;
            """, page)

        XCTAssert(!result.toBool(), "Found a result for empty selector")
    }

    func testQuerySelectorAll() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("\(testServerURL)/querySelector/simple.html");

            const items = await page.querySelectorAll('div.item');
            return items.length
            """, page)

        XCTAssertEqual(result.toInt32(), 2, "Received unexepcted amount of elements: \(result.toInt32())")
    }

    func testQuerySelectorAllOfAnElement() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("\(testServerURL)/querySelector/simple.html");

            const listEl = await page.querySelector('ul');
            const items = await listEl.querySelectorAll('li');

            return items.length
            """, page)

        XCTAssertEqual(result.toInt32(), 2, "Received unexepcted amount of elements: \(result.toInt32())")
    }

    func testQuerySelectorAndGetAttribute() async throws {
        let page = PipeablePage(webView)
        let result = try await runScript(
            """
            await page.goto("\(testServerURL)/querySelector/simple.html");

            const selectCompound = await page.querySelector('div.item');
            const attribute = await selectCompound?.getAttribute("data-testid");

            return attribute;
            """, page)

        XCTAssertEqual(result.toString(), "TestID Attribute 1")
    }
}
