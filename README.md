# Pipeable SDK for iOS

_Currently in alpha state_

Check out our blog post announcing the release of Pipeable for iOS: [Introducing Pipeable](https://www.pipeable.com/blog/introducing-pipeable).

To quickly try out a sample app, check out our [Samples repository](https://github.com/PipeableHQ/pipeable-ios-samples).

## Introduction

Pipeable is a WebView automation framework similar to Puppeteer / Playwright which allows the developer to script a sequence of action to be performed inside a WebView.

It is inspired by the design of browser automation frameworks and exposes an API that is very similar.

Example:

```swift
try await page.goto("https://news.ycombinator.com/")

let searchForm = try await page.waitForXPath(
    "//form[contains(@action, 'hn.algolia.com')]",
    visible: true
)

let textAreaEl = try await searchForm?.querySelector("input[type='text']")
try await textAreaEl?.type("web automation")

_ = try await page.submitActiveForm()

try await page.waitForURL { url in url.contains("hn.algolia") }

try await page.waitForSelector(".Story_title", visible: true)

let stories = try await page.querySelectorAll(".Story_title")

var storyTitles: [String] = []

for story in stories {
    if let title = try await story.textContent() {
        storyTitles.append(title)
    }
}

print(storyTitles)
```

## Installation

Pipeable is distrbuted through Swift Package Manager and CocoaPods.

1. Using Swift Package Manager:

- Select your project's target settings
- Under "Frameworks, Libraries, and Embedded Content" select "+"
- Add Other... -> Add Package Dependency
- In the "Search or Enter Pacakge URL" enter: https://github.com/PipeableHQ/pipeable-ios.git

2. Using CocoaPods

- In your `Podfile` add

```
pod 'PipeableSDK'
```

- Run `pod install`

## Quick start

### Initialization

The starting point of every automation is the `PipeablePage` object. It binds to a `WKWebView` and is used to drive user interaction with the page's elements and to read back contents off the page.

```swift
import PipeableSDK

let webView = PipeableWebView()
let page = webView.page
```

### Navigation

Navigating to a page is done using the `.goto(url: String, waitUntil: WaitUntilOptions = .load, timeout: Int = 30_000)` method.

The options for `waitUntil` are `domcontentloaded`, `load`, and `networkidle`.

```swift
try await page.goto("https://myaddress.com")
```

### Selecting elements

Selecting an element can be done via querySelectors and xpath. For example:

```swift
let element = try await page.querySelector("#id.class")
if let element = element {
  // Do something with the element.
}

let xpathSelector = try await page.xpathSelector("//div[contains(string(), 'Text on page')]");

// There are also waitFor* versions of the selectors, which wait until elements are attached or become visible

let visibleElement = try await page.waitForSelector(".appears_with_delay", visible: true)

// We can also query the subtrees of elements for other elements. E.g.

let container = try await page.querySelector("#container")

let items = try await container!.querySelectorAll(".item")
```

### Interacting with elements

One can click, hover, select, focus and type on elements.

```swift
try await element.click();
try await element.type("Text", /* delay in ms between characters*/ 10)
```

### Waiting for events

When we interact with a page, we often need to listen to what's happening on the page and react accordingly.

Here are some tools to do that:

```swift

try await page.waitForURL({ url in url == "http://site.com/goal_page"}, timeout: 30_000)

let repsonse = try await page.waitForResponse({ res in res.url == "http://site.com/api/async_api" })
```
