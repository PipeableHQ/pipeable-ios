@testable import PipeableSDK
import XCTest

final class ScriptTests: XCTestCase {
    func test_goto() async throws {
        let result = try await runScript("""
            print('Calling page.goto');
            await fakePage.goto("https://google.com");
            return true;
        """)

        XCTAssertTrue(result.isBoolean && result.toBool(), "Unexpected result! " + result.debugDescription)
    }

    func test_goto_with_error() async throws {
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

    func test_querySelector_and_click() async throws {
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

    func test_querySelector_and_click_with_error() async throws {
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
}
