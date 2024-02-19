@testable import PipeableSDK

import WebKit
import XCTest

final class PageLoadStateTests: XCTestCase {
    func testSuccessfullyInvokingListener() async throws {
        let pageLoadState = PageLoadState()

        let expectation = XCTestExpectation(description: "Listener is invoked")

        _ = pageLoadState.subscribeToLoadStateChange { state, url, error in
            expectation.fulfill()
            XCTAssertEqual(state, .load)
            XCTAssertEqual(url, "random_url")
            XCTAssert(error == nil)

            return true
        }

        pageLoadState.changeState(state: .load, url: "random_url")
        await fulfillment(of: [expectation])

        // Validate that the listener is no longer there, since we returned a true
        XCTAssertEqual(
            pageLoadState.activeListenersCount,
            0,
            "Listener count not 0: \(pageLoadState.activeListenersCount)"
        )
    }

    func testRemovingAListenerWithFunction() async throws {
        let pageLoadState = PageLoadState()

        let expectation = XCTestExpectation(description: "Listener is invoked")

        let removeListener1 = pageLoadState.subscribeToLoadStateChange { _, _, _ in
            // Do not automatically remove the listener
            false
        }

        let removeListener2 = pageLoadState.subscribeToLoadStateChange { _, _, _ in
            // Do not automatically remove the listener
            expectation.fulfill()
            return false
        }

        XCTAssertEqual(pageLoadState.activeListenersCount, 2)

        removeListener1()

        XCTAssertEqual(pageLoadState.activeListenersCount, 1)

        pageLoadState.changeState(state: .load, url: "random_url")

        await fulfillment(of: [expectation])

        // Still 1 listener, since it was not removed.
        XCTAssertEqual(pageLoadState.activeListenersCount, 1)

        removeListener2()

        XCTAssertEqual(pageLoadState.activeListenersCount, 0)
    }

    func testErrorHandling() async throws {
        let pageLoadState = PageLoadState()
        let expectation = XCTestExpectation(description: "Error listener is invoked")
        let testError = PipeableError.navigationError("Terminated.")

        _ = pageLoadState.subscribeToLoadStateChange { state, url, error in
            XCTAssertEqual(state, .notloaded)
            XCTAssertEqual(url, "error_url")
            XCTAssertNotNil(error)
            if let error = error as? PipeableError {
                if case PipeableError.navigationError(let reason) = error {
                    XCTAssertEqual(reason, "Terminated.")
                    expectation.fulfill()
                } else {
                    XCTFail("Expected PipeableError.navigationError, but got a different error: \(error)")
                }
            } else {
                XCTFail("Error not PipeableError")
            }

            return true
        }

        pageLoadState.error(error: testError, url: "error_url")
        await fulfillment(of: [expectation])

        XCTAssertEqual(
            pageLoadState.activeListenersCount,
            0,
            "Listener count not 0: \(pageLoadState.activeListenersCount)"
        )
    }

    func testMultipleListeners() async throws {
        let pageLoadState = PageLoadState()
        let expectation1 = XCTestExpectation(description: "First listener is invoked")
        let expectation2 = XCTestExpectation(description: "Second listener is invoked")

        _ = pageLoadState.subscribeToLoadStateChange { state, _, _ in
            XCTAssertEqual(state, .domcontentloaded)
            expectation1.fulfill()
            return false
        }

        _ = pageLoadState.subscribeToLoadStateChange { state, _, _ in
            XCTAssertEqual(state, .domcontentloaded)
            expectation2.fulfill()
            return false
        }

        pageLoadState.changeState(state: .domcontentloaded, url: "test_url")
        await fulfillment(of: [expectation1, expectation2])

        XCTAssertEqual(pageLoadState.activeListenersCount, 2, "Expected 2 listeners to remain active")
    }

    func testNoDuplicateRemovals() async throws {
        let pageLoadState = PageLoadState()
        let removeListener = pageLoadState.subscribeToLoadStateChange { _, _, _ in false }

        XCTAssertEqual(pageLoadState.activeListenersCount, 1, "Should have 1 active listener initially")

        removeListener()
        XCTAssertEqual(pageLoadState.activeListenersCount, 0, "Should have no active listeners after removal")

        // Attempt to remove the listener again
        removeListener()
        XCTAssertEqual(
            pageLoadState.activeListenersCount,
            0,
            "Should still have no active listeners after attempting duplicate removal"
        )
    }
}
