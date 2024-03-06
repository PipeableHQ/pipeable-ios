@testable import PipeableSDK
import WebKit
import XCTest

final class PipeablePageEvaluateTests: PipeableXCTestCase {
    func testEvaluateSync() async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("about:blank")

        let simpleIntResult = try await page.evaluate("1 + 2")
        XCTAssertEqual(simpleIntResult as? Int, 3)

        let simpleStringResult = try await page.evaluate("'hello'")
        XCTAssertEqual(simpleStringResult as? String, "hello")

        let simpleArrayResult = try await page.evaluate("[1, 2, 3]")
        XCTAssertEqual(simpleArrayResult as? [Int], [1, 2, 3])
    }

    func testEvaluateAsync() async throws {
        let page = PipeablePage(webView)

        _ = try? await page.goto("about:blank")

        let functionalEvaluation = try await page.evaluateAsyncFunction(
            """
                return url;
            """, arguments: ["url": "sampleUrl"]
        )
        XCTAssertEqual(functionalEvaluation as? String, "sampleUrl")

        let complexReturnValue = try await page.evaluateAsyncFunction(
            """
                return [
                    [
                        { a: 1, b: 2 },
                        { a: 3, b: 4 },
                    ],
                    1,
                    2,
                    'string',
                ];
            """)

        if let complexReturnValue = complexReturnValue {
            // Stringify the result.
            let data = try JSONSerialization.data(withJSONObject: complexReturnValue, options: [])
            let stringified = String(data: data, encoding: .utf8)
            XCTAssertEqual(stringified, "[[{\"a\":1,\"b\":2},{\"a\":3,\"b\":4}],1,2,\"string\"]")
        } else {
            XCTFail("complexReturnValue is nil")
        }

        let complexAsyncReturnValue = try await page.evaluateAsyncFunction(
            """
                return (async function () {
                    await new Promise(f => setTimeout(f, 100));
                    return {
                        a: 1,
                        b: 'string',
                        c: [1, 2, 3],
                    };
                })();
            """)

        if let complexAsyncReturnValue = complexAsyncReturnValue {
            let data = try JSONSerialization.data(withJSONObject: complexAsyncReturnValue, options: [])
            let stringified = String(data: data, encoding: .utf8)
            XCTAssertEqual(stringified, "{\"a\":1,\"b\":\"string\",\"c\":[1,2,3]}")
        } else {
            XCTFail("complexAsyncReturnValue is nil")
        }
    }

    func testEvaluateWithPipeableElement() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
            "\(testServerURL)/load_latency/0/index.html",
            waitUntil: .networkidle
        )

        guard let element = try await page.querySelector("#container a") else {
            XCTFail("Element not found")
            return
        }

        let textContentOfElement = try await page.evaluateAsyncFunction(
            """
                return el.textContent
            """, arguments: ["el": element]
        )

        XCTAssertEqual(textContentOfElement as? String, "Another Page")
    }

    func testEvaluateWithPipeableElementsArray() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
            "\(testServerURL)/load_latency/0/index.html",
            waitUntil: .networkidle
        )

        let elements = try await page.querySelectorAll("ul li")

        let sumOfValues = try await page.evaluateAsyncFunction(
            """
                let sum = 0;
                for (const el of elements) {
                    sum += parseInt(el.getAttribute('data-val'), 10);
                }

                return sum;
            """, arguments: ["elements": elements]
        )

        XCTAssertEqual(sumOfValues as? Int, 10)
    }

    func testEvaluateWithPipeableElementsDictionary() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
            "\(testServerURL)/load_latency/0/index.html",
            waitUntil: .networkidle
        )

        guard let linkEl = try await page.querySelector("#container a") else {
            XCTFail("Link el not found")
            return
        }

        let elements = try await page.querySelectorAll("ul li")

        let sumOfValuesAndText = try await page.evaluateAsyncFunction(
            """
                let sum = 0;
                for (const el of obj.elements) {
                    sum += parseInt(el.getAttribute('data-val'), 10);
                }

                const linkText = obj.link.textContent;

                return linkText + ' ' + sum;
            """, arguments: [
                "obj":
                    [
                        "elements": elements,
                        "link": linkEl
                    ]
            ]
        )

        XCTAssertEqual(sumOfValuesAndText as? String, "Another Page 10")
    }

    func testEvaluateWithClickOnElement() async throws {
        let page = PipeablePage(webView)

        _ = try await page.goto(
            "\(testServerURL)/load_latency/0/index.html",
            waitUntil: .networkidle
        )

        guard let linkEl = try await page.querySelector("#container a") else {
            XCTFail("Link el not found")
            return
        }

        _ = try await page.evaluateAsyncFunction("el.click()", arguments: ["el": linkEl])
        try await page.waitForURL({ url in url.contains("another.html") }, timeout: 5_000)
    }
}
