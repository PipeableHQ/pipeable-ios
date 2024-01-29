@testable import PipeableSDK
import XCTest

final class ScriptTests: XCTestCase {
    func test_goto() async throws {
        let result = try await runScript("""
            print('Calling page.goto');
            await page.goto("https://google.com");
            return true;
        """)

        XCTAssertTrue(result.isBoolean && result.toBool(), "Unexpected result! " + result.debugDescription)
    }

    func test_goto_with_error() async throws {
        let script = """
            print('Calling page.goto');
            await page.goto("");
            return true;
        """
        do {
            _ = try await runScript(script)
            XCTFail("An empty url error is expected")
        } catch let ScriptError.error(reason) {
            XCTAssertEqual(reason, "Empty url parameter")
        } catch {
            XCTFail("An empty url error is expected")
        }
    }
}
