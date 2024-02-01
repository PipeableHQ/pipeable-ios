import Foundation
import PipeableSDK

func loginAmazon(page: PipeablePage, year: Int) async throws {
    try await page.goto("https://www.amazon.com/gp/css/order-history/ref=ppx_yo2ov_mob_b_filter_y\(year)_all?ie=UTF8&digitalOrders=0&orderFilter=year-\(year)&search=&startIndex=0&unifiedOrders=0")

    // TODO: waitForURL doesn't get triggered for URLs that are not final, and these are redirect URLs. We can detect them in another way, but what API do we use for that? waitForResponse?

    try await page.waitForURL { url in
        url.contains("orderFilter=year-\(year)")
    }
}

func fetchPurchasesFromAmazon(page: PipeablePage) async throws -> [ListEntry] {
    var orders: [ListEntry] = []

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

            let anOrder = ListEntry(item: imageAlt ?? "", date: orderDate ?? "")
            orders.append(anOrder)
        }
    }

    return orders
}
