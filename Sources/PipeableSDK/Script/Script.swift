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
            if let exceptionDictionary = exception.toDictionary() {
                if let line = exceptionDictionary["line"] as? NSNumber {
                    context.evaluateScript("__errorLine = \(line)")
                }
            }
            if let exceptionObject = exception.toObject() {
                context.evaluateScript("__errorRawObject = `\(exceptionObject)`")
            }

            // Print the exception, set it as the error of the script, so it's passed to "runScript".
            let script = "__error = `\(exception.description)`"
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

public struct ScriptErrorInfo {
    let stack: String?
    let line: Int?
    let column: Int?

    // The raw stringified Error object returned from the JS script. Used for debugging purposes.
    let rawObject: String?
}

public enum ScriptError: Error {
    case error(reason: String, info: ScriptErrorInfo)
    case unexpectedError
}

// The offset when reporting error lines calculated based on the main script below.
private let mainScriptLineOffset = 2
private func buildMainScript(_ script: String) -> String {
    return """
    async function asyncCallWithError() {
        __context.scriptStarted();
        \(script)
    }

    // Put as much as possible code after asyncCallWithError so that
    // there are less changes to the script line offset.

    var __error = undefined;
    var __errorStack = undefined;
    var __errorLine = undefined;
    var __errorColumn = undefined;
    var __errorRawObject = undefined;
    var __result = undefined;

    asyncCallWithError().then(
        (result) => {
            __result = result;
            __context.scriptEnded();
        },
        (e) => {
            __error = e.toString();

            if(e.stack) {
                __errorStack = e.stack;
            }

            if(e.line) {
                __errorLine = e.line;
            }

            if(e.column) {
                __errorColumn = e.column;
            }

            if(e instanceof Error) {
                __errorRawObject = JSON.stringify(e, Object.getOwnPropertyNames(e));
            }

            __context.scriptEnded();
        }
    );
    """
}

public func runScript(_ script: String, _ page: PipeablePage? = nil) async throws -> JSValue {
    return try await withCheckedThrowingContinuation { continuation in
        // Use a DispatchGroup so that we wait for the script and all async functions to finish before returning
        let dispatchGroup = DispatchGroup()
        let context = prepareJSContext(dispatchGroup, page)

        context.evaluateScript(buildMainScript(script))

        dispatchGroup.notify(queue: .main) {
            if let error = context.objectForKeyedSubscript("__error") {
                if !error.isUndefined {
                    let stack = getStringFromJSValue(context.objectForKeyedSubscript("__errorStack"))
                    let line = getLineFromJSValue(context.objectForKeyedSubscript("__errorLine"))
                    let column = getIntFromJSValue(context.objectForKeyedSubscript("__errorColumn"))
                    let rawObject = getStringFromJSValue(context.objectForKeyedSubscript("__errorRawObject"))

                    continuation.resume(throwing: ScriptError.error(
                        reason: error.toString(),
                        info: ScriptErrorInfo(stack: stack, line: line, column: column, rawObject: rawObject)))
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

private func getStringFromJSValue(_ jsValue: JSValue) -> String? {
    if jsValue.isString {
        return jsValue.toString()
    }
    return nil
}

private func getIntFromJSValue(_ jsValue: JSValue) -> Int? {
    if jsValue.isNumber {
        return jsValue.toNumber().intValue
    }
    return nil
}

private func getLineFromJSValue(_ jsValue: JSValue) -> Int? {
    if let line = getIntFromJSValue(jsValue) {
        return line - mainScriptLineOffset
    }
    return nil
}
