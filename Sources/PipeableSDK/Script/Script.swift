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

enum CompletionResult {
    case error(String)
    case success(NSObject?)
}

class BaseWrapper: NSObject {
    let dispatchGroup: DispatchGroup
    init(_ dispatchGroup: DispatchGroup) {
        self.dispatchGroup = dispatchGroup
        super.init()
    }

    func doWithCompletion(_ completionHandler: JSValue, _ call: @escaping () async throws -> CompletionResult) {
        dispatchGroup.enter()

        @Sendable
        func taskRun() async {
            defer {
                self.dispatchGroup.leave()
            }
            do {
                let result = try await call()
                switch result {
                case let .error(error):
                    completionHandler.call(withArguments: [["error": error]])
                case let .success(result):
                    if let result = result {
                        completionHandler.call(withArguments: [["result": result]])
                    } else {
                        completionHandler.call(withArguments: [[:]])
                    }
                }
            } catch {
                completionHandler.call(withArguments: [["error": "Unexpected error \(error)"]])
            }
        }
        Task {
            await taskRun()
        }
    }
}

class PipeableElementWrapper: BaseWrapper, PipeableElementJSExport {
    let element: FakePipeableElement
    var successFullClicksClount = 0

    init(_ dispatchGroup: DispatchGroup, _ element: FakePipeableElement) {
        self.element = element
        super.init(dispatchGroup)
    }

    func clickWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            do {
                try await self.element.click()
                self.successFullClicksClount += 1
            } catch PipeableError.elementNotFound {
                completionHandler.call(withArguments: [["error": "Element not found."]])
            }
            return CompletionResult.success(nil)
        }
    }
}

@objc protocol PageJSExport: JSExport {
    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
class PageWrapper: BaseWrapper, PageJSExport {
    let page: FakePage

    override init(_ dispatchGroup: DispatchGroup) {
        self.page = FakePage()
        super.init(dispatchGroup)
    }

    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            do {
                try await self.page.goto(url)
            } catch let PipeableError.navigationError(errorMessage) {
                completionHandler.call(withArguments: [["error": "\(errorMessage)"]])
            }
            return CompletionResult.success(nil)
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let element = try await self.page.querySelector(selector)
            if let element = element {
                return CompletionResult.success(PipeableElementWrapper(self.dispatchGroup, element))
            }
            return CompletionResult.success(nil)
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
    function completionToAsync(functionName) {
        return function(...args) {
            return new Promise((resolve, reject) => {
                this[functionName](...args, function(result) {
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
    }

    PageWrapper.prototype.goto = completionToAsync("gotoWithCompletion");
    PageWrapper.prototype.querySelector = completionToAsync("querySelectorWithCompletion");
    PipeableElementWrapper.prototype.click = completionToAsync("clickWithCompletion");
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
