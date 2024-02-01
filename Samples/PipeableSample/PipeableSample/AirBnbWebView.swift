import Foundation
import PipeableSDK
import SwiftUI
import WebKit

struct AirBnbWebView: View {
    @Binding var orders: [ListEntry]
    var onClose: () -> Void
    var onResult: (ResultStatus) -> Void

    @State var working = false
    @State var done = false
    @State var statusText = ""
    @State var statusAnimated = false

    var body: some View {
        ZStack {
            WebViewWrapper(orders: $orders, onClose: onClose, onStatusChange: onStatusChange)
                .blur(radius: working ? 2.5 : 0)
                .allowsHitTesting(!working)
        }
    }

    func onStatusChange(_ status: Status, _ newOrders: [ListEntry]) {
        orders = newOrders

        if status == .login {
            statusText = "👤  Please log into your account"
            statusAnimated = false
            working = false
        } else if status == .working {
            statusText = "🤖  Robot working, please wait"
            statusAnimated = true
            working = true
        } else if status == .done {
            statusText = "✅  Orders fetched!"
            statusAnimated = false
            working = false
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.success)
            }
        } else if status == .failure {
            statusText = "❌  Could not complete operation"
            statusAnimated = false
            working = false
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.failure)
            }
        }
    }
}

private struct WebViewWrapper: UIViewControllerRepresentable {
    @Binding var orders: [ListEntry]

    var onClose: () -> Void
    var onStatusChange: (_ status: Status, _ orders: [ListEntry]) -> Void
    var initialized = false

    // This function makes the WKWebView
    func makeUIViewController(context: UIViewControllerRepresentableContext<WebViewWrapper>) -> WKWebViewController {
        let uiViewController = WKWebViewController(onClose: onClose, onStatusChange: onStatusChange)
        uiViewController.orders = orders
        return uiViewController
    }

    // This function is called when the WKWebView is created to load the request
    func updateUIViewController(_ uiViewController: WKWebViewController, context: UIViewControllerRepresentableContext<WebViewWrapper>) {
        if uiViewController.isStarted {
            return
        }

        Task {
            do {
                try await uiViewController.start()
            } catch {
                print("An unexpected error occurred: \(error)")
            }
        }
    }
}

private class WKWebViewController: UIViewController {
    var webView: WKWebView
    var isStarted = false
    var onClose: () -> Void
    var onStatusChange: (_ status: Status, _ orders: [ListEntry]) -> Void
    var orders: [ListEntry] = []

    init(onClose: @escaping () -> Void, onStatusChange: @escaping (_ status: Status, _ orders: [ListEntry]) -> Void) {
        self.webView = WKWebView()
        self.onClose = onClose
        self.onStatusChange = onStatusChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()

        // Set up resizing rules.
        webView = WKWebView(frame: .zero)

        // Only for iOS versions above 16.4
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        let closeButtonItem = BlockBarButtonItem(title: "Close", style: .plain) {
            self.webView.stopLoading()
            self.webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            self.onClose()
        }

        // Create a toolbar
        let toolbar = UIToolbar()
        toolbar.items = [closeButtonItem]
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        view.addSubview(toolbar)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.leftAnchor.constraint(equalTo: view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])
    }

    func start() async throws {
        // No re-entry.
        isStarted = true

        let page = PipeablePage(webView)

//        page.deleteAllCookies()

        onStatusChange(.login, [])

        try await loginAirBnB(page: page)

        onStatusChange(.working, [])

        do {
            orders = try await fetchTripsFromAirbnb(page: page)
            onStatusChange(.done, orders)
        } catch {
            onStatusChange(.failure, [])
        }
    }
}

struct AirBnbWebView_Previews: PreviewProvider {
    @State private static var orders: [ListEntry] = []

    static var previews: some View {
        VStack {
            AirBnbWebView(orders: $orders, onClose: {}, onResult: { _ in })
        }
    }
}
