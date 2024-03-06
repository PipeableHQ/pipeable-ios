import Foundation
import WebKit

public extension PipeablePage {
    /// Evaluates a JavaScript expression synchronously.
    /// - Parameter javascript: The JavaScript expression to evaluate.
    /// - Returns: The result of the evaluation.
    /// - Throws: An error if the JavaScript evaluation fails.
    func evaluate(_ javascript: String) async throws -> Any? {
        let evaluationScript = """
            (function () {
                var result = (() => \(javascript))();
                return result !== undefined ? result : null;
            })();
        """

        let result = try await webView.evaluateJavaScript(
            evaluationScript,
            in: frame,
            contentWorld: WKContentWorld.page
        )

        return result
    }

    /// Evaluates a JavaScript function asynchronously.
    ///
    /// - Parameters:
    ///   - javascript: The body of the javascript function to evaluate. It
    ///     should not start with the function definition, but start straight
    ///     with the function body. The arguments provided in the `arguments`
    ///     parameter will be available as variables in the function body.
    ///
    /// - arguments: A dictionary of arguments to pass to the function. The
    ///   valid types are:
    ///   - PipeableElement: The element to pass to the function.
    ///   - Basic types: Int, String, etc.
    ///   - Collections (arrays and dictionaries) of the above types.
    ///
    /// - Returns: The result of the function. Can return a promise or a value.
    ///
    /// - Throws: An error if the JavaScript evaluation fails or if the
    ///   provided arguments are not valid.
    ///
    func evaluateAsyncFunction(_ javascript: String, arguments: [String: Any] = [:]) async throws -> Any? {
        let (modifiedArguments, didSubstite) = replacePipeableElementsInFunctionArguments(in: arguments)

        var functionToInvoke = javascript

        if didSubstite {
            functionToInvoke = """
                function substitutePipeableElements(value) {
                    if (value._type === 'pipeableElement') {
                        return window.SophiaJS.getElement(value.elementId);
                    } else if (Array.isArray(value)) {
                        return value.map(substitutePipeableElements);
                    } else if (typeof value === 'object') {
                        for (var key in value) {
                            value[key] = substitutePipeableElements(value[key]);
                        }
                    }
                    return value;
                }

                for (var key in arguments) {
                    arguments[key] = substitutePipeableElements(arguments[key]);
                }

                \(javascript)
            """
        }

        let result = try await webView.callAsyncJavaScript(
            functionToInvoke,
            arguments: modifiedArguments,
            in: frame,
            contentWorld: WKContentWorld.page
        )

        return result
    }
}

private func replacePipeableElementsInFunctionArguments(in arguments: [String: Any]) -> (modified: [String: Any], didSubstite: Bool) {
    func replacePipeableElements(in value: Any) -> (modified: Any, didSubstite: Bool) {
        switch value {
        case let pipeableElement as PipeableElement:
            // If it's identifiable, return its id
            return ([
                "_type": "pipeableElement",
                "elementId": pipeableElement.elementId,
            ], true)
        case var dictionary as [String: Any]:
            // If it's a dictionary, replace identifiable elements in its values
            var didSubstitute = false
            for (key, value) in dictionary {
                let (modifiedValue, substituted) = replacePipeableElements(in: value)
                dictionary[key] = modifiedValue
                didSubstitute = didSubstitute || substituted
            }
            return (dictionary, didSubstitute)
        case var array as [Any]:
            // If it's an array, replace identifiable elements in its items
            var didSubstitute = false
            for i in 0 ..< array.count {
                let (modifiedValue, substituted) = replacePipeableElements(in: array[i])
                array[i] = modifiedValue
                didSubstitute = didSubstitute || substituted
            }
            return (array, didSubstitute)
        default:
            // If it's neither, return it unchanged
            return (value, false)
        }
    }

    let (modifiedArguments, didSubstite) = replacePipeableElements(in: arguments)
    return (modifiedArguments as! [String: Any], didSubstite)
}
