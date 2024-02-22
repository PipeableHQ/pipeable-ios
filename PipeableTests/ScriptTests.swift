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
        } catch let ScriptError.error(reason) {
            XCTAssertEqual(reason, "Navigation error: Empty url")
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
        } catch let ScriptError.error(reason) {
            XCTAssertEqual(reason, "Element not found.")
        } catch {
            XCTFail("An empty url error is expected")
        }
    }

    func testScriptWithUnhandledExceptions() async throws {
        let script = "random statement that should not compile"
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason) {
            XCTAssertEqual(reason, """
            SyntaxError: Unexpected identifier 'statement'
            {
                line = 5;
            }
            """)
        }
    }

    func testScriptWithNonExistentFunctions() async throws {
        let script = "nonexistentFunctionCall()"
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason) {
            XCTAssert(reason.contains("ReferenceError"), "Script failed with unhandled exception \(reason)")
        }
    }

    func testScriptWithSyntaxError() async throws {
        let script = "1 + - = 3"
        do {
            _ = try await runScript(script)
            XCTFail("Should fail with unhandled exception.")
        } catch let ScriptError.error(reason) {
            XCTAssertEqual(reason, """
            SyntaxError: Unexpected token '='
            {
                line = 5;
            }
            """)
        }
    }
}
