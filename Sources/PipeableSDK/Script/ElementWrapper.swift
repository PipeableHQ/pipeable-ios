import Foundation
import JavaScriptCore

@objc protocol ElementJSExport: JSExport {
    func clickWithCompletion(_ completionHandler: JSValue)
}

class ElementWrapper: BaseWrapper, ElementJSExport {
    let element: PipeableElement

    init(_ dispatchGroup: DispatchGroup, _ element: PipeableElement) {
        self.element = element
        super.init(dispatchGroup)
    }

    func clickWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            try await self.element.click()
            return CompletionResult.success(nil)
        }
    }
}
