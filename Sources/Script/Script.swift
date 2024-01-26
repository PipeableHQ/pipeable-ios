import Foundation
import JavaScriptCore

enum UrlError: Error {
    case emptyUrl
}

let dispatchGroup = DispatchGroup()

// This is a fake Page that will be replaced by the real page.
class FakePage {
    func goto(_ url: String) async throws {
        if url.isEmpty {
            throw UrlError.emptyUrl
        }
        print("Navigating to url: \(url) ...")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("Navigation completed!")
    }
}

@objc protocol PageJSExport: JSExport {
    static func create() -> PageWrapper
    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue)
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
class PageWrapper: NSObject, PageJSExport {
    let page: FakePage

    class func create() -> PageWrapper {
        return PageWrapper()
    }

    override init() {
        self.page = FakePage()
        super.init()
    }

    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue) {
        @Sendable
        func taskRun() async {
            dispatchGroup.enter()
            defer {
                dispatchGroup.leave()
            }
            do {
                try await page.goto(url)
                completionHandler.call(withArguments: [[:]])
            } catch UrlError.emptyUrl {
                completionHandler.call(withArguments: [["error": "Empty url parameter"]])
            } catch {
                completionHandler.call(withArguments: [["error": "Unexpected error \(error)"]])
            }
        }
        Task {
            await taskRun()
        }
    }
}

public func prepareJSContext() -> (JSContext, DispatchGroup) {
    // swiftlint:disable:next force_unwrapping
    let context = JSContext()!
    context.exceptionHandler = { _, error in print("\(String(describing: error))") }

    let printFunc: @convention(block) (String) -> Void = { text in print(text) }
    context.setObject(
        unsafeBitCast(printFunc, to: AnyObject.self),
        forKeyedSubscript: "print" as NSCopying & NSObjectProtocol)

    // Set exception handler
    context.exceptionHandler = { _, exception in
        if let exception = exception {
            print("JS Error: \(exception)")
        }
    }

    let page = PageWrapper()

    context.setObject(page, forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))

    context.evaluateScript("""
    page.goto = function(url) {
        return new Promise((resolve, reject) => {
            this.gotoWithCompletion(url, function(result) {
                if (result && result.error) {
                    reject(result.error);
                } else {
                    resolve();
                }
            });
        });
    }
    page.goto = page.goto.bind(page);
    """)

    return (context, dispatchGroup)
}
