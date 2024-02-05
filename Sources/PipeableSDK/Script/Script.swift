import Foundation
import JavaScriptCore

public func prepareJSContext(_ dispatchGroup: DispatchGroup, _ page: PipeablePage? = nil) -> JSContext {
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

    let fakePage = FakePageWrapper(dispatchGroup)
    let scriptContext = ScriptContext(dispatchGroup)

    context.setObject(scriptContext, forKeyedSubscript: "__context" as (NSCopying & NSObjectProtocol))
    if let page = page {
        let pageWrapper = PageWrapper(dispatchGroup, page)
        context.setObject(pageWrapper, forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))
    }

    context.setObject(PageWrapper.self, forKeyedSubscript: "PageWrapper" as (NSCopying & NSObjectProtocol))
    context.setObject(
        ElementWrapper.self,
        forKeyedSubscript: "ElementWrapper" as (NSCopying & NSObjectProtocol))

    context.setObject(fakePage, forKeyedSubscript: "fakePage" as (NSCopying & NSObjectProtocol))
    context.setObject(FakePageWrapper.self, forKeyedSubscript: "FakePageWrapper" as (NSCopying & NSObjectProtocol))
    context.setObject(
        FakeElementWrapper.self,
        forKeyedSubscript: "FakeElementWrapper" as (NSCopying & NSObjectProtocol))

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

    FakePageWrapper.prototype.goto = completionToAsync("gotoWithCompletion");
    FakePageWrapper.prototype.querySelector = completionToAsync("querySelectorWithCompletion");
    FakeElementWrapper.prototype.click = completionToAsync("clickWithCompletion");

    PageWrapper.prototype.goto = completionToAsync("gotoWithCompletion");
    PageWrapper.prototype.querySelector = completionToAsync("querySelectorWithCompletion");
    ElementWrapper.prototype.click = completionToAsync("clickWithCompletion");
    """)

    return context
}

public enum ScriptError: Error {
    case error(reason: String)
    case unexpectedError
}

public func runScript(_ script: String, _ page: PipeablePage? = nil) async throws -> JSValue {
    return try await withCheckedThrowingContinuation { continuation in
        let dispatchGroup = DispatchGroup()
        let context = prepareJSContext(dispatchGroup, page)
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
