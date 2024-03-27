import Foundation
import WebKit

/// A wrapper around `WKWebView` that provides a `PipeablePage` instance
public class PipeableWebView: WKWebView {
    /// The `PipeablePage` instance associated with the WebView
    public lazy var page: PipeablePage = .init(self)

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
