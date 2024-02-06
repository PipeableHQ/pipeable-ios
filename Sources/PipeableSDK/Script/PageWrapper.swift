import Foundation
import JavaScriptCore

@objc protocol PageJSExport: JSExport {
    func gotoWithCompletion(_ url: String, _ timeout: Int, _ waitUntilRaw: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
    func url() -> URL?
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
final class PageWrapper: BaseWrapper, PageJSExport {
    let page: PipeablePage

    init(_ dispatchGroup: DispatchGroup, _ page: PipeablePage) {
        self.page = page
        super.init(dispatchGroup)
    }

    func gotoWithCompletion(_ url: String, _ timeout: Int, _ waitUntilRaw: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let waitUntil = PipeablePage.WaitUntilOption(rawValue: waitUntilRaw)
            guard let waitUntil = waitUntil else {
                throw PipeableError.invalidParameter("Invalid waitUntil option passed: \(waitUntilRaw)")
            }

            try await self.page.goto(url, timeout: timeout, waitUntil: waitUntil)
            return CompletionResult.success(nil)
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let element = try await self.page.querySelector(selector)
            if let element = element {
                return CompletionResult.success(ElementWrapper(self.dispatchGroup, element))
            }
            return CompletionResult.success(nil)
        }
    }

    func url() -> URL? {
        return page.url()
    }
}
