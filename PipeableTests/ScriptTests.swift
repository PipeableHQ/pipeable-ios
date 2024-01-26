@testable import Pipeable
import XCTest

final class ScriptTests: XCTestCase {
    func test_goto() throws {
        let (context, dispatchGroup) = prepareJSContext()
        context.evaluateScript("""
        var result = {};
        async function asyncCallWithError() {
            try {
                print('Calling page.goto');
                await page.goto("https://google.com");
                result.success = true;
            }
            catch(e) {
                print(`Error caught: ${e}`);
                result.error = e;
            }
        }
        asyncCallWithError()
        """)

        dispatchGroup.wait()
        if let error = context.objectForKeyedSubscript("result").objectForKeyedSubscript("error") {
            XCTAssertTrue(error.isUndefined || error.isNull, "Unexpected Error from JavaScript: \(error)")
        }
    }

    func test_goto_with_error() throws {
        let (context, dispatchGroup) = prepareJSContext()
        context.evaluateScript("""
        var result = {};
        async function asyncCallWithError() {
            try {
                print('Calling page.goto');
                await page.goto("");
                result.success = true;
            }
            catch(e) {
                print(`Error caught: ${e}`);
                result.error = e;
            }
        }
        asyncCallWithError()
        """)

        dispatchGroup.wait()
        if let error = context.objectForKeyedSubscript("result").objectForKeyedSubscript("error") {
            XCTAssertFalse(error.isUndefined || error.isNull, "Expected error not found")
        }
    }
}
