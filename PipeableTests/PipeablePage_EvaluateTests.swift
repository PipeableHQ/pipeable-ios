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
}
