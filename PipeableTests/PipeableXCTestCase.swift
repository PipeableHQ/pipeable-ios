import Foundation
import WebKit
import XCTest

class PipeableXCTestCase: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    var webView: WKWebView!

    override func setUp() {
        super.setUp()
        webView = WKWebView()
    }

    override func tearDown() {
        webView = nil
        super.tearDown()
    }
}
