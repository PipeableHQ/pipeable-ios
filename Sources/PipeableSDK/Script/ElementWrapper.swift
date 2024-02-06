import Foundation
import JavaScriptCore

@objc protocol ElementJSExport: JSExport {
    func clickWithCompletion(_ completionHandler: JSValue)
    func textContentWithCompletion(_ completionHandler: JSValue)
    func getAttributeWithCompletion(_ attributeName: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
    func querySelectorAllWithCompletion(_ selector: String, _ completionHandler: JSValue)
}

final class ElementWrapper: BaseWrapper, ElementJSExport {
    let element: PipeableElement
    let context: JSContext

    init(_ dispatchGroup: DispatchGroup, _ element: PipeableElement, _ context: JSContext) {
        self.element = element
        self.context = context
        super.init(dispatchGroup)
    }

    func clickWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            try await self.element.click()
            return CompletionResult.success(nil)
        }
    }

    func textContentWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let value = try await self.element.textContent()
            if let value = value {
                return CompletionResult.success(value as NSString)
            } else {
                return CompletionResult.success(nil)
            }
        }
    }

    func getAttributeWithCompletion(_ attributeName: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let value = try await self.element.getAttribute(attributeName)

            if let value = value {
                return CompletionResult.success(value as NSString)
            } else {
                return CompletionResult.success(nil)
            }
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let element = try await self.element.querySelector(selector)
            if let element = element {
                return CompletionResult.success(ElementWrapper(self.dispatchGroup, element, self.context))
            }
            return CompletionResult.success(nil)
        }
    }

    func querySelectorAllWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let elements = try await self.element.querySelectorAll(selector)
            let wrappedElementsInArray = try elements.map {
                let wrapper = ElementWrapper(self.dispatchGroup, $0, self.context)
                guard let val = JSValue(object: wrapper, in: self.context) else {
                    throw PipeableError.fatalError("Could not allocate JS Object for ElementWrapper")
                }

                return val
            }

            guard let jsArray = JSValue(newArrayIn: self.context) else {
                throw PipeableError.fatalError("Could not initialize array")
            }

            for jsObject in wrappedElementsInArray {
                jsArray.invokeMethod("push", withArguments: [jsObject])
            }

            return CompletionResult.success(jsArray)
        }
    }
}
