import Foundation
import PipeableSDK

func loginAirBnB(page: PipeablePage) async throws {
    try await page.goto("https://www.airbnb.com/login")

    try await page.waitForURL { url in
        url == "https://www.airbnb.com/"
    }
}

func fetchTripsFromAirbnb(page: PipeablePage) async throws -> [ListEntry] {
    try await page.goto("https://www.airbnb.com/trips/v1")

    // One option is to parse the data from the response.
    // It's arguable the more stable one, but for the sake of demonstration,
    // we're using the DOM.
//    _ = try await page.waitForXHR("TripsQuery", timeout: 30000)

    _ = try await page.waitForSelector("div[data-testid='reservation-card'", visible: true)

    var orders: [ListEntry] = []

    let trips = try await page.querySelectorAll("div[data-testid='reservation-card'")

    if !trips.isEmpty {
        for trip in trips {
            let textLineEls = try await trip.querySelectorAll("span")
            if textLineEls.count != 3 {
                continue
            }

            let placeEl = textLineEls[0]
            let periodEl = textLineEls[2]

            let placeText = try await placeEl.textContent()
            let periodText = try await periodEl.textContent()

            let entry = ListEntry(item: placeText ?? "", date: periodText ?? "")
            orders.append(entry)
        }
    }

    return orders
}
