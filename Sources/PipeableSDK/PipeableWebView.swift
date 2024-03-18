import Foundation
import WebKit

public class PipeableWebView: WKWebView {
    public lazy var page: PipeablePage = .init(self)

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
