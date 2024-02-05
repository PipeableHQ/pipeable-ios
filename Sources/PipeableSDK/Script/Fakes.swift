import Foundation
import JavaScriptCore

// Fakes are temporary used for testing. Will be removed soon.

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

@objc protocol FakeElementJSExport: JSExport {
    func clickWithCompletion(_ completionHandler: JSValue)
}

class FakeElementWrapper: BaseWrapper, FakeElementJSExport {
    let element: FakePipeableElement
    var successFullClicksClount = 0

    init(_ dispatchGroup: DispatchGroup, _ element: FakePipeableElement) {
        self.element = element
        super.init(dispatchGroup)
    }

    func clickWithCompletion(_ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            try await self.element.click()
            self.successFullClicksClount += 1
            return CompletionResult.success(nil)
        }
    }
}

@objc protocol FakePageJSExport: JSExport {
    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue)
    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue)
}

// Page wrapper wraps the Page Swift API so that it makes it easy/possible to implement the Page Script API.
class FakePageWrapper: BaseWrapper, FakePageJSExport {
    let page: FakePage

    override init(_ dispatchGroup: DispatchGroup) {
        self.page = FakePage()
        super.init(dispatchGroup)
    }

    func gotoWithCompletion(_ url: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            try await self.page.goto(url)
            return CompletionResult.success(nil)
        }
    }

    func querySelectorWithCompletion(_ selector: String, _ completionHandler: JSValue) {
        doWithCompletion(completionHandler) {
            let element = try await self.page.querySelector(selector)
            if let element = element {
                return CompletionResult.success(FakeElementWrapper(self.dispatchGroup, element))
            }
            return CompletionResult.success(nil)
        }
    }
}
