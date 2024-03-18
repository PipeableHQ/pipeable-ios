import Foundation
import PipeableSDK
import SwiftUI
import WebKit

struct PipeableWebViewWrapper: UIViewRepresentable {
    @Binding var items: [NewsItem]
    var onClose: () -> Void

    func makeUIView(context _: Context) -> PipeableWebView {
        let webView = PipeableWebView()
        let page = webView.page

        Task {
            _ = try? await page.goto("https://news.ycombinator.com", waitUntil: .networkidle)

            try? await sleep(ms: 1000)

            let searchForm = try await page.waitForXPath(
                "//form[contains(@action, 'hn.algolia.com')]",
                visible: true
            )

            guard let textAreaEl = try await searchForm?.querySelector("input[type='text']") else {
                return
            }

            _ = try await page.evaluateAsyncFunction(
                """
                    el.scrollIntoView();

                    el.focus();

                    await new Promise((res) => setTimeout(res, 500));

                    // Scroll a bit to the top, so we can visualize what we are typing.

                    window.scrollTo(0, window.scrollY + 300);
                """, arguments: ["el": textAreaEl]
            )

            try? await sleep(ms: 1000)

            try await textAreaEl.type("web automation", delay: 50)

            _ = try await page.submitActiveForm()

            try await page.waitForURL { url in url.contains("hn.algolia") }

            _ = try await page.waitForSelector(".Story_title", visible: true)

            // For demo purposes only: hold the screen a bit, so it's visible.
            // Not required for the actual automation, just like the other sleep()s.
            try? await sleep(ms: 2000)

            let stories = try await page.querySelectorAll(".Story_title a > span")

            items = []

            var storyTitles: [String] = []

            for story in stories {
                if let title = try await story.textContent() {
                    items.append(NewsItem(itemName: title))
                    storyTitles.append(title)
                }
            }

            print(storyTitles)

            onClose()
        }

        return webView
    }

    func updateUIView(_: PipeableWebView, context _: Context) {
        // Since our demo app is very simple, everything happens during creation
        // and no ui view updates are triggered.
    }
}

func sleep(ms: UInt64) async throws {
    try await Task.sleep(nanoseconds: ms * 1000000)
}

struct PipeableWebview_Previews: PreviewProvider {
    @State private static var items: [NewsItem] = []

    static var previews: some View {
        VStack {
            PipeableWebViewWrapper(items: $items) {}
        }
    }
}
