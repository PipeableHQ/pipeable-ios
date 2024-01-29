import Foundation
import PipeableSDK
import SwiftUI
import WebKit

enum ResultStatus {
    case success
    case failure
}

struct PipeableWebView: View {
    @Binding var orders: [AmazonOrder]
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

    func onStatusChange(_ status: Status, _ newOrders: [AmazonOrder]) {
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

enum Status {
    case login
    case working
    case done
    case failure
}

struct WebViewWrapper: UIViewControllerRepresentable {
    @Binding var orders: [AmazonOrder]

    var onClose: () -> Void
    var onStatusChange: (_ status: Status, _ orders: [AmazonOrder]) -> Void
    var initialized = false

    // This function makes the WKWebView
    func makeUIViewController(context: UIViewControllerRepresentableContext<WebViewWrapper>) -> WKWebViewController {
        let uiViewController = WKWebViewController(onClose: onClose, onStatusChange: onStatusChange)
        uiViewController.orders = orders
        return uiViewController
    }

    func makeCoordinator() -> WebViewCoordinator {
        return WebViewCoordinator(self)
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

    mutating func urlChanged(url: URL, webView: WKWebView) {
    }
}


class WKWebViewController: UIViewController {
    var webView: WKWebView
    var isStarted = false
    var onClose: (() -> Void)
    var onStatusChange: ((_ status: Status, _ orders: [AmazonOrder]) -> Void)
    var orders: [AmazonOrder] = []

    init(onClose: @escaping () -> Void, onStatusChange: @escaping (_ status: Status, _ orders: [AmazonOrder]) -> Void) {
        self.webView = WKWebView()
        self.onClose = onClose
        self.onStatusChange = onStatusChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()

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

        self.view.addSubview(webView)
        self.view.addSubview(toolbar)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: self.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            toolbar.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            toolbar.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: self.view.rightAnchor),
        ])
    }

    func start() async throws {
        // No re-entry.
        isStarted = true

        let year = 2023
        let page = PipeablePage(webView, nil)

        onStatusChange(.login, [])

        try await page.goto("https://www.amazon.com/gp/css/order-history/ref=ppx_yo2ov_mob_b_filter_y\(year)_all?ie=UTF8&digitalOrders=0&orderFilter=year-\(year)&search=&startIndex=0&unifiedOrders=0")

        // TODO: waitForURL doesn't get triggered for URLs that are not final, and these are redirect URLs. We can detect them in another way, but what API do we use for that? waitForResponse?

        try await page.waitForURL { url in
            url.contains("orderFilter=year-\(year)")
        }


        onStatusChange(.working, [])
        do {
            let ordersEls = try await page.querySelectorAll("#ordersContainer .js-item")

            if !ordersEls.isEmpty {
                for orderEl in ordersEls {
                    let orderImage = try await orderEl.querySelector("img")
                    let imageAlt = try await orderImage?.getAttribute("alt")

                    let orderDateEl = try await orderEl.querySelector(".a-size-small")

                    let orderDateRawText = try await orderDateEl?.textContent()
                    let orderDate = orderDateRawText?
                        .replacingOccurrences(
                            of: "Ordered on",
                            with: "",
                            options: .caseInsensitive
                        )
                        .replacingOccurrences(
                            of: "Delivered",
                            with: "",
                            options: .caseInsensitive
                        )
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    let anOrder = AmazonOrder(item: imageAlt ?? "", date: orderDate ?? "")
                    orders.append(anOrder)
                }
            }

            onStatusChange(.done, orders)
        } catch {
            onStatusChange(.failure, orders)
            return
        }
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    var parent: WebViewWrapper

    init(_ parent: WebViewWrapper) {
        self.parent = parent
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            print("Request URL: \(url)")
            parent.urlChanged(url: url, webView: webView)
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
        if let url = webView.url {
            print("Finished loading URL: \(url)")
            // Perform actions based on the URL that finished loading

            webView.evaluateJavaScript("SophiaJS.version()")

            // Delay this by 3 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Your code here will be run after 3 seconds
                webView.evaluateJavaScript("SophiaJS.clickOnXPath('//button[contains(string(), \"OK\")]')")
                //                webView.evaluateJavaScript("SophiaBridge.version()");
            }
        }
    }
}

public func deleteAllCookies() {
    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dateFrom = Date(timeIntervalSince1970: 0)

    dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) { }
}


struct Cookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
}

public func getCookiesJSON(webView: WKWebView) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            await MainActor.run {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let cookieObjects = cookies.map {
                        Cookie(
                            name: $0.name,
                            value: $0.value,
                            domain: $0.domain,
                            path: $0.path
                        )
                    }
                    do {
                        let jsonData = try JSONEncoder().encode(cookieObjects)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            continuation.resume(returning: jsonString)
                        } else {
                            continuation.resume(throwing: NSError(domain: "Invalid JSON data", code: -1, userInfo: nil))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
public func getUserAgent(webView: WKWebView) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            await MainActor.run {
                webView.evaluateJavaScript("navigator.userAgent") { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let userAgent = result as? String {
                        continuation.resume(returning: userAgent)
                    } else {
                        continuation.resume(returning: "")
                    }
                }
            }
        }
    }
}

class BlockBarButtonItem: UIBarButtonItem {
    private var actionHandler: (() -> Void)?

    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(title: title, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }

    convenience init(image: UIImage?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(image: image, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }

    @objc func barButtonItemPressed(sender: UIBarButtonItem) {
        actionHandler?()
    }
}

struct PipeableWebview_Previews: PreviewProvider {
    @State static private var orders: [AmazonOrder] = []

    static var previews: some View {
        VStack {
            PipeableWebView(orders: $orders, onClose: {}, onResult: { _ in })
        }
    }
}
