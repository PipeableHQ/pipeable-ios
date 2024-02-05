import Foundation
import JavaScriptCore

enum CompletionResult {
    case error(String)
    case success(NSObject?)
}

class BaseWrapper: NSObject {
    let dispatchGroup: DispatchGroup
    init(_ dispatchGroup: DispatchGroup) {
        self.dispatchGroup = dispatchGroup
        super.init()
    }

    func doWithCompletion(_ completionHandler: JSValue, _ call: @escaping () async throws -> CompletionResult) {
        dispatchGroup.enter()

        @Sendable
        func taskRun() async {
            defer {
                self.dispatchGroup.leave()
            }
            do {
                let result = try await call()
                switch result {
                case let .error(error):
                    completionHandler.call(withArguments: [["error": error]])
                case let .success(result):
                    if let result = result {
                        completionHandler.call(withArguments: [["result": result]])
                    } else {
                        completionHandler.call(withArguments: [[:]])
                    }
                }
            } catch let PipeableError.navigationError(errorMessage) {
                completionHandler.call(withArguments: [["error": "Navigation error: \(errorMessage)"]])
            } catch PipeableError.elementNotFound {
                completionHandler.call(withArguments: [["error": "Element not found."]])
            } catch {
                completionHandler.call(withArguments: [["error": "Unexpected error \(error)"]])
            }
        }
        Task {
            await taskRun()
        }
    }
}
