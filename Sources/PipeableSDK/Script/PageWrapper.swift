import Foundation
import JavaScriptCore

@objc protocol PageJSExport: JSExport {
    func gotoWithCompletion(_ url: String, _ timeout: Int, _ waitUntilRaw: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
    func querySelectorAllWithCompletion(_ selector: String, _ completionHandler: JSValue)
    func url() -> URL?
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
final class PageWrapper: BaseWrapper, PageJSExport {
    let page: PipeablePage
    let context: JSContext

    init(_ dispatchGroup: DispatchGroup, _ page: PipeablePage, _ context: JSContext) {
        self.page = page
        self.context = context
        super.init(dispatchGroup)
    }

    func gotoWithCompletion(_ url: String, _ timeout: Int, _ waitUntilRaw: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let waitUntil = PipeablePage.WaitUntilOption(rawValue: waitUntilRaw)
            guard let waitUntil = waitUntil else {
                throw PipeableError.invalidParameter("Invalid waitUntil option passed: \(waitUntilRaw)")
            }

            _ = try await self.page.goto(url, waitUntil: waitUntil, timeout: timeout)
            return CompletionResult.success(nil)
        }
    }

    func reloadWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            try await self.page.reload()
            return CompletionResult.success(nil)
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let element = try await self.page.querySelector(selector)
            if let element = element {
                return CompletionResult.success(ElementWrapper(self.dispatchGroup, element, self.context))
            }
            return CompletionResult.success(nil)
        }
    }

    func querySelectorAllWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let elements = try await self.page.querySelectorAll(selector)
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

    @MainActor
    func url() -> URL? {
        return page.url()
    }
}
