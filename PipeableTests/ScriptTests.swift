@testable import Pipeable
import XCTest

final class ScriptTests: XCTestCase {
    func test_goto() throws {
        let result = runScript("""
        print('Calling page.goto');
        await page.goto("https://google.com");
        return true;
        """)

        XCTAssertTrue(try result.get().toBool(), "Unexpected result!")
    }

    func test_goto_with_error() throws {
        let result = runScript("""
        print('Calling page.goto');
        await page.goto("");
        return true;
        """)

        XCTAssertThrowsError(try result.get(), "An empty url error is expected")
    }
}
