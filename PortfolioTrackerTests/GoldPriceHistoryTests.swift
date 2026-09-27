//
//  GoldPriceHistoryTests.swift
//  PortfolioTrackerTests
//
//  Dane do wykresu ceny złota w tle.
//

import Foundation
import Testing
@testable import PortfolioTracker

struct GoldPriceHistoryTests {

    @Test func builtInDataCovers1975To2025() {
        let points = GoldPriceHistory.combined(monthly: [])
        let calendar = Calendar(identifier: .gregorian)
        #expect(points.count == 51)
        #expect(calendar.component(.year, from: points.first!.date) == 1975)
        #expect(calendar.component(.year, from: points.last!.date) == 2025)
        #expect(points.allSatisfy { $0.price > 0 })
    }

    @Test func monthlyDataReplacesAnnualAveragesFromItsStart() {
        let start = GoldPriceHistory.midYear(2000).addingTimeInterval(60 * 86_400) // ~09.2000
        let monthly = [
            GoldPricePoint(date: start, price: 273),
            GoldPricePoint(date: start.addingTimeInterval(31 * 86_400), price: 265),
        ]
        let points = GoldPriceHistory.combined(monthly: monthly)
        // 1975-2000 (średnia za 2000 jest przed startem danych miesięcznych) + 2 punkty miesięczne.
        #expect(points.count == 26 + 2)
        #expect(points.last?.price == 265)
        #expect(points.map(\.date) == points.map(\.date).sorted())
    }
}
