import Foundation
import JavaScriptCore

// Temporarily silencing swiftlint until we refactor this into building blocks
// swiftlint:disable:next function_body_length
public func prepareJSContext(_ dispatchGroup: DispatchGroup, _ page: PipeablePage? = nil) -> JSContext {
    guard let context = JSContext() else {
        fatalError("Failed to initialize JSContext")
    }

    let printFunc: @convention(block) (String) -> Void = { text in print(text) }
    context.setObject(
        unsafeBitCast(printFunc, to: AnyObject.self),
        forKeyedSubscript: "print" as NSCopying & NSObjectProtocol)

    // Set exception handler
    context.exceptionHandler = { _, exception in
        if let exception = exception {
            // Print the exception, set it as the error of the script, so it's passed to "runScript".
            var errorMessage = exception.description
            if let exceptionObject = exception.toObject() {
                errorMessage = "\(errorMessage)\n\(exceptionObject)"
            }

            let script = "__error = `" + errorMessage + "`"
            context.evaluateScript(script)
        }
    }

    let fakePage = FakePageWrapper(dispatchGroup)
    let scriptContext = ScriptContext(dispatchGroup)

    context.setObject(scriptContext, forKeyedSubscript: "__context" as (NSCopying & NSObjectProtocol))
    if let page = page {
        let pageWrapper = PageWrapper(dispatchGroup, page, context)
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

    PageWrapper.prototype.goto = function (url, opts) {
        var timeout = 30_000;
        var waitUntil = 'load';

        if (opts !== undefined) {
            if (opts.timeout !== undefined && opts.timeout !== null) {
                timeout = Number(opts.timeout);
                if (isNaN(timeout)) {
                    return Promise.reject("Invalid timeout: " + opts.timeout);
                }
            }

            if (opts.waitUntil !== undefined && opts.waitUntil !== null) {
                waitUntil = opts.waitUntil;
                if (waitUntil !== 'load' && waitUntil !== 'domcontentloaded' && waitUntil !== 'networkidle') {
                    return Promise.reject("Invalid waitUntil: " + opts.waitUntil);
                }
            }
        }

        var rawFunc = completionToAsync("gotoWithCompletion").bind(this);
        return rawFunc(url, timeout, waitUntil);
    };

    PageWrapper.prototype.querySelector = completionToAsync("querySelectorWithCompletion");
    PageWrapper.prototype.querySelectorAll = completionToAsync("querySelectorAllWithCompletion");

    ElementWrapper.prototype.click = completionToAsync("clickWithCompletion");
    ElementWrapper.prototype.textContent = completionToAsync("textContentWithCompletion");
    ElementWrapper.prototype.getAttribute = completionToAsync("getAttributeWithCompletion");
    ElementWrapper.prototype.querySelector = completionToAsync("querySelectorWithCompletion");
    ElementWrapper.prototype.querySelectorAll = completionToAsync("querySelectorAllWithCompletion");
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
                    // TODO: Figure out how to convert back to PipeableErrors the PipeableError's, so that ScriptError is just a JS error.
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
