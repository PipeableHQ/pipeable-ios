import Foundation

class PageLoadState {
    // We start in a not loaded state and then go through the different stages.
    // They are determined through the delegate for domcontentloaded and then
    // from javascript on the page itself for the other types.
    private(set) var state: LoadState = .notloaded
    private var loadError: Error?
    private var currentURL: String?
    private var callbacks: [CallbackWrapper] = []

    private let synchronizationQueue = DispatchQueue(label: "waitForURL")

    // Define a struct to wrap the callback so we can compare them by reference.
    // Required for removing the specific callback from the
    private class CallbackWrapper {
        let callback: LoadStateChangeCallback

        init(callback: @escaping LoadStateChangeCallback) {
            self.callback = callback
        }
    }

    typealias LoadStateChangeCallback = (_ state: LoadState, _ url: String?, _ error: Error?) -> Bool

    func changeState(state: LoadState, url: String?) {
        self.state = state
        currentURL = url
        loadError = nil

        signalLoadStateChange()
    }

    func error(error: Error, url: String?) {
        state = .notloaded
        loadError = error
        currentURL = url

        signalLoadStateChange()
    }

    /// Subscribe to the load state change.
    /// - Parameter callback: The callback to be called when the load state
    /// changes. The callback should return true if it wants to be removed from
    /// the list of subscribers.
    /// - Returns: A function that can be called to unsubscribe from the load
    func subscribeToLoadStateChange(_ callback: @escaping LoadStateChangeCallback) -> () -> Void {
        let wrapper = CallbackWrapper(callback: callback)

        synchronizationQueue.sync {
            // Add the callback to the list of subscribers.
            callbacks.append(wrapper)
        }

        return { [weak self] in
            self?.synchronizationQueue.sync {
                // Remove the callback from the list of subscribers.
                if let index = self?.callbacks.firstIndex(where: { $0 === wrapper }) {
                    self?.callbacks.remove(at: index)
                }
            }
        }
    }

    var activeListenersCount: Int {
        return callbacks.count
    }

    private func signalLoadStateChange() {
        synchronizationQueue.sync {
            // Signal all the subscribers that the load state has changed.
            for (index, callback) in callbacks.enumerated() where callback.callback(state, currentURL, loadError) {
                callbacks.remove(at: index)
            }
        }
    }
}

enum LoadState: Int {
    case notloaded = 0
    case domcontentloaded = 1
    case load = 2
    case networkidle = 3

    static func fromWaitUntil(_ waitUntilOption: PipeablePage.WaitUntilOption) -> LoadState {
        switch waitUntilOption {
        case .load:
            return .load
        case .domcontentloaded:
            return .domcontentloaded
        case .networkidle:
            return .networkidle
        }
    }

    static func fromString(_ stringvalue: String) -> LoadState? {
        switch stringvalue {
        case "domcontentloaded":
            return .domcontentloaded
        case "load":
            return .load
        case "networkidle":
            return .networkidle
        default:
            return nil
        }
    }
}
