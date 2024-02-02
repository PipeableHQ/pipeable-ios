import JavaScriptCore

@objc protocol ScriptContextJSExport: JSExport {
    func scriptStarted()
    func scriptEnded()
}

final class ScriptContext: NSObject, ScriptContextJSExport {
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
