@testable import PipeableSDK
import XCTest

final class ScriptTests: XCTestCase {
    func testGoto() async throws {
        let result = try await runScript("""
            print('Calling page.goto');
            await fakePage.goto("https://google.com");
            return true;
        """)

        XCTAssertTrue(result.isBoolean && result.toBool(), "Unexpected result! " + result.debugDescription)
    }

    func testGotoWithError() async throws {
        let script = """
            print('Calling page.goto');
            await fakePage.goto("");
            return true;
        """
        do {
            _ = try await runScript(script)
            XCTFail("An empty url error is expected")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "NavigationError: Empty url")
            XCTAssertNil(info.line)
            XCTAssertNil(info.column)
            XCTAssertNil(info.stack)
        } catch {
            XCTFail("An empty url error is expected")
        }
    }

    func testQuerySelectorAndClick() async throws {
        let script = """
            const element = await fakePage.querySelector("asd");
            await element.click();
            return element;
        """
        let result = try await runScript(script)
        // swiftlint:disable:next force_cast
        let element = result.toObjectOf(FakeElementWrapper.self) as! FakeElementWrapper
        XCTAssertEqual(element.successFullClicksClount, 1)
    }

    func testQuerySelectorAndClickWithError() async throws {
        let script = """
            const element = await fakePage.querySelector("empty");
            await element.click();
            return element;
        """
        do {
            _ = try await runScript(script)
            XCTFail("Element not found error is expected")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "PipeableError: Element not found.")
            XCTAssertNil(info.line)
            XCTAssertNil(info.column)
            XCTAssertNil(info.stack)
        } catch {
            XCTFail("An empty url error is expected")
        }
    }

    func testScriptWithNonExistentFunctions() async throws {
        let script = "nonexistentFunctionCall()"
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "ReferenceError: Can't find variable: nonexistentFunctionCall")
            XCTAssertEqual(info.line, 1)
            XCTAssertEqual(info.column, 28)
            XCTAssertEqual(info.stack, """
            @
            asyncCallWithError@
            global code@
            """)
        }
    }

    func testScriptErrorWithUndefinedIsNotAnObject() async throws {
        let script = """
        var test = undefined;
        test.toStr();
        """
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "TypeError: undefined is not an object (evaluating 'test.toStr')")
            XCTAssertEqual(info.line, 2)
            XCTAssertEqual(info.column, 5)
            XCTAssertEqual(info.stack, """
            @
            asyncCallWithError@
            global code@
            """)
        }
    }

    func testScriptWithSyntaxError() async throws {
        let script = "1 + - = 3"
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "SyntaxError: Unexpected token '='")
            XCTAssertEqual(info.line, 1)
            XCTAssertNil(info.column)
            XCTAssertNil(info.stack)
            XCTAssertEqual(info.rawObject, """
            {
                line = 3;
            }
            """)
        }
    }

    func testScriptWithSyntaxErrorOn3rdLine() async throws {
        let script = """
        var a = 5;
        var b = 7;
        1 + - = 3
        """

        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason, info) {
            XCTAssertEqual(reason, "SyntaxError: Unexpected token '='")
            XCTAssertEqual(info.line, 3)
            XCTAssertNil(info.stack)
            XCTAssertNil(info.column)
            XCTAssertEqual(info.rawObject, """
            {
                line = 5;
            }
            """)
        }
    }
}
