import Foundation
import JavaScriptCore

// This is a fake Page that will be replaced by the real page.
class FakePage {
    func goto(_ url: String) async throws {
        if url.isEmpty {
            throw PipeableError.navigationError("Empty url")
        }
        print("Navigating to url: \(url) ...")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("Navigation completed!")
    }

    public func querySelector(_ selector: String) async throws -> FakePipeableElement? {
        if selector.isEmpty {
            return nil
        }
        if selector == "empty" {
            return FakePipeableElement(self, "")
        }
        return FakePipeableElement(self, "id-123")
    }
}

class FakePipeableElement {
    var page: FakePage
    let elementId: String

    init(_ page: FakePage, _ elementId: String) {
        self.page = page
        self.elementId = elementId
    }

    public func click() async throws {
        if elementId.isEmpty {
            throw PipeableError.elementNotFound
        }
        print("Clicking on element with id: \(elementId) ...")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("Click completed!")
    }
}

@objc protocol ScriptContextJSExport: JSExport {
    func scriptStarted()
    func scriptEnded()
}

class ScriptContext: NSObject, ScriptContextJSExport {
    let dispatchGroup: DispatchGroup

    init(_ dispatchGroup: DispatchGroup) {
        self.dispatchGroup = dispatchGroup
        super.init()
    }

    func scriptStarted() {
        dispatchGroup.enter()
    }

    func scriptEnded() {
        Task {
            self.dispatchGroup.leave()
        }
    }
}

@objc protocol PipeableElementJSExport: JSExport {
    func clickWithCompletion(_ completionHandler: JSValue)
}

class PipeableElementWrapper: NSObject, PipeableElementJSExport {
    let element: FakePipeableElement
    let dispatchGroup: DispatchGroup
    var successFullClicksClount = 0

    init(_ dispatchGroup: DispatchGroup, element: FakePipeableElement) {
        self.element = element
        self.dispatchGroup = dispatchGroup
        super.init()
    }

    func clickWithCompletion(_ completionHandler: JSValue) {
        dispatchGroup.enter()

        @Sendable
        func taskRun() async {
            defer {
                self.dispatchGroup.leave()
            }
            do {
                try await element.click()
                successFullClicksClount += 1
                completionHandler.call(withArguments: [[:]])
            } catch PipeableError.elementNotFound {
                completionHandler.call(withArguments: [["error": "Element not found."]])
            } catch {
                completionHandler.call(withArguments: [["error": "Unexpected error \(error)"]])
            }
        }
        Task {
            await taskRun()
        }
    }
}

@objc protocol PageJSExport: JSExport {
    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
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
        dispatchGroup.enter()

        @Sendable
        func taskRun() async {
            defer {
                self.dispatchGroup.leave()
            }
            do {
                try await page.goto(url)
                completionHandler.call(withArguments: [[:]])
            } catch PipeableError.navigationError(let errorMessage) {
                completionHandler.call(withArguments: [["error": "\(errorMessage)"]])
            } catch {
                completionHandler.call(withArguments: [["error": "Unexpected error \(error)"]])
            }
        }
        Task {
            await taskRun()
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        dispatchGroup.enter()

        @Sendable
        func taskRun() async {
            defer {
                self.dispatchGroup.leave()
            }
            do {
                let element = try await page.querySelector(selector)
                // swiftlint:disable:next force_unwrapping
                let wrapped = element != nil ? PipeableElementWrapper(dispatchGroup, element: element!) : nil
                completionHandler.call(withArguments: [["result": wrapped]])
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
    let scriptContext = ScriptContext(dispatchGroup)

    context.setObject(scriptContext, forKeyedSubscript: "__context" as (NSCopying & NSObjectProtocol))
    context.setObject(page, forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))
    context.setObject(PageWrapper.self, forKeyedSubscript: "PageWrapper" as (NSCopying & NSObjectProtocol))
    context.setObject(
        PipeableElementWrapper.self,
        forKeyedSubscript: "PipeableElementWrapper" as (NSCopying & NSObjectProtocol))

    context.evaluateScript("""
    PageWrapper.prototype.goto = function(url) {
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
    PageWrapper.prototype.querySelector = function(selector) {
        return new Promise((resolve, reject) => {
            this.querySelectorWithCompletion(selector, function(result) {
                if (result && result.error) {
                    reject(result.error);
                } else if (result && result.result) {
                    resolve(result.result);
                } else {
                    resolve();
                }
            });
        });
    }
    PipeableElementWrapper.prototype.click = function() {
        return new Promise((resolve, reject) => {
            this.clickWithCompletion(function(result) {
                if (result && result.error) {
                    reject(result.error);
                } else if (result && result.result) {
                    resolve(result.result);
                } else {
                    resolve();
                }
            });
        });
    }
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
            __context.scriptStarted()
            \(script)
        }
        asyncCallWithError().then(
            (result) => {
                __result = result;
                __context.scriptEnded()
            },
            (e) => {
                __error = e.toString();
                __context.scriptEnded()
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
