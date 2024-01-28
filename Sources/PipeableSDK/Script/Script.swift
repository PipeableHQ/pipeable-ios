import Foundation
import JavaScriptCore

enum UrlError: Error {
    case emptyUrl
}

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
    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue)
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
class PageWrapper: NSObject, PageJSExport {
    let page: FakePage
    let dispatchGroup: DispatchGroup

    init(_ dispatchGroup: DispatchGroup) {
        self.page = FakePage()
        self.dispatchGroup = dispatchGroup
        super.init()
    }

    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue) {
        @Sendable
        func taskRun() async {
            dispatchGroup.enter()
            defer {
                self.dispatchGroup.leave()
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

public func prepareJSContext(_ dispatchGroup: DispatchGroup) -> JSContext {
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

    let page = PageWrapper(dispatchGroup)

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

    return context
}

public enum ScriptError: Error {
    case error(reason: String)
    case unexpectedError
}

public func runScript(_ script: String) async throws -> JSValue {
    return try await withCheckedThrowingContinuation { continuation in
        let dispatchGroup = DispatchGroup()
        let context = prepareJSContext(dispatchGroup)
        context.evaluateScript("""
        var __error = undefined;
        var __result = undefined;
        async function asyncCallWithError() {
            \(script)
        }
        asyncCallWithError().then(
            (result) => {
                __result = result;
            },
            (e) => {
                __error = e.toString();
            }
        );
        """)

        dispatchGroup.notify(queue: .main) {
            if let error = context.objectForKeyedSubscript("__error") {
                if !error.isUndefined {
                    continuation.resume(throwing: ScriptError.error(reason: error.toString()))
                    return
                }
            }

            if let result = context.objectForKeyedSubscript("__result") {
                continuation.resume(returning: result)
                return
            }

            continuation.resume(throwing: ScriptError.unexpectedError)
        }
    }
}
