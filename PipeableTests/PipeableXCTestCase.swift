import Foundation
import WebKit
import XCTest

class PipeableXCTestCase: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    var webView: WKWebView!

    override func setUp() {
        super.setUp()

        webView = WKWebView(frame: UIScreen.main.bounds)

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
    }

    override func tearDown() {
        webView = nil
        super.tearDown()
    }
}
