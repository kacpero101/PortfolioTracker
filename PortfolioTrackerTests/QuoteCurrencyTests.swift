//
//  QuoteCurrencyTests.swift
//  PortfolioTrackerTests
//
//  Testy przeliczania cen z waluty notowania Yahoo Finance (meta.currency) na USD.
//

import Foundation
import Testing
@testable import PortfolioTracker

struct QuoteCurrencyTests {

    private let rates: [String: Double] = ["PLN": 0.25, "EUR": 1.10, "GBP": 1.30, "ZAR": 0.055]

    private func approxEqual(_ lhs: Double?, _ rhs: Double) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) < 0.000001
    }

    @Test func usdQuoteIsUnchanged() {
        #expect(QuoteCurrency.priceInUSD(price: 190.5, currency: "USD", usdRates: [:]) == 190.5)
        #expect(QuoteCurrency.requiredRateCurrency(for: "USD") == nil)
    }

    @Test func missingCurrencyIsTreatedAsUSD() {
        #expect(QuoteCurrency.priceInUSD(price: 42, currency: nil, usdRates: [:]) == 42)
        #expect(QuoteCurrency.priceInUSD(price: 42, currency: "", usdRates: [:]) == 42)
        #expect(QuoteCurrency.requiredRateCurrency(for: nil) == nil)
    }

    @Test func plnQuoteIsConvertedToUSD() {
        // CDR.WA notowany na GPW w PLN.
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 200, currency: "PLN", usdRates: rates), 50))
        #expect(QuoteCurrency.requiredRateCurrency(for: "PLN") == "PLN")
    }

    @Test func eurQuoteIsConvertedToUSD() {
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 100, currency: "EUR", usdRates: rates), 110))
    }

    @Test func lowercaseCodeIsNormalized() {
        #expect(QuoteCurrency.normalize(price: 10, currency: "eur").currency == "EUR")
    }

    @Test func penceAreConvertedToPoundsThenUSD() {
        // Np. IWDA.L / VUSA.L: 7 500 GBp = 75 GBP.
        let normalized = QuoteCurrency.normalize(price: 7500, currency: "GBp")
        #expect(normalized.currency == "GBP")
        #expect(approxEqual(normalized.price, 75))
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 7500, currency: "GBp", usdRates: rates), 97.5))
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 7500, currency: "GBX", usdRates: rates), 97.5))
        #expect(QuoteCurrency.requiredRateCurrency(for: "GBp") == "GBP")
    }

    @Test func poundsAreNotDividedBy100() {
        // "GBP" (funty) różni się od "GBp" (pensy) tylko wielkością litery.
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 75, currency: "GBP", usdRates: rates), 97.5))
    }

    @Test func southAfricanCentsAreConvertedToRand() {
        #expect(approxEqual(QuoteCurrency.priceInUSD(price: 1000, currency: "ZAc", usdRates: rates), 0.55))
    }

    @Test func missingRateReturnsNil() {
        #expect(QuoteCurrency.priceInUSD(price: 100, currency: "JPY", usdRates: rates) == nil)
    }
}
