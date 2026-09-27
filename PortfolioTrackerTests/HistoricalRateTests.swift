//
//  HistoricalRateTests.swift
//  PortfolioTrackerTests
//
//  Kurs waluty z dnia zakupu transzy.
//

import Foundation
import Testing
@testable import PortfolioTracker

struct HistoricalRateTests {

    // Dzienne świece EURUSD=X z Yahoo (znaczniki czasu = początek sesji, 23:00 UTC dnia poprzedniego).
    let timestamps: [Double] = [1_789_945_200, 1_790_031_600, 1_790_118_000, 1_790_204_400, 1_790_290_800]
    let closes: [Double?] = [1.1479, 1.1464, nil, 1.1381, 1.1374]

    @Test func picksLastSessionOnOrBeforePurchase() {
        let purchase = Date(timeIntervalSince1970: 1_790_050_000) // w trakcie 2. sesji
        #expect(HistoricalRate.closeOnOrBefore(purchase, timestamps: timestamps, closes: closes) == 1.1464)
    }

    @Test func skipsMissingCloses() {
        let purchase = Date(timeIntervalSince1970: 1_790_150_000) // 3. sesja nie ma zamknięcia
        #expect(HistoricalRate.closeOnOrBefore(purchase, timestamps: timestamps, closes: closes) == 1.1464)
    }

    @Test func weekendPurchaseUsesLastTradingDay() {
        let purchase = Date(timeIntervalSince1970: 1_790_290_800 + 2 * 86_400)
        #expect(HistoricalRate.closeOnOrBefore(purchase, timestamps: timestamps, closes: closes) == 1.1374)
    }

    @Test func purchaseBeforeAllCandlesFallsBackToEarliest() {
        let purchase = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(HistoricalRate.closeOnOrBefore(purchase, timestamps: timestamps, closes: closes) == 1.1479)
        #expect(HistoricalRate.closeOnOrBefore(purchase, timestamps: [], closes: []) == nil)
    }

    @MainActor @Test func historicalRateIsNotOverwrittenByTemporaryRate() {
        let lot = PurchaseLot(date: Date(), quantity: 1, price: 100, purchaseCurrency: "EUR", purchaseCurrencyRate: nil)
        var asset = Asset(name: "BTC", ticker: "BTC", type: .crypto, lots: [lot])
        #expect(asset.lots[0].needsHistoricalRate)

        PortfolioStore.setPurchaseRate(1.10, historical: true, lotID: lot.id, in: &asset)
        PortfolioStore.setPurchaseRate(1.25, historical: false, lotID: lot.id, in: &asset)

        #expect(asset.lots[0].purchaseCurrencyRate == 1.10)
        #expect(!asset.lots[0].needsHistoricalRate)
        #expect(abs(asset.lots[0].costBasisUSD - 110) < 0.000_001)
    }

    @Test func legacyRateIsTreatedAsTemporary() throws {
        let json = #"{"id":"3CE713C9-C1CD-4733-901C-6C8504BD0CA0","date":"2026-09-27T08:23:03Z","quantity":1,"price":100,"purchaseCurrency":"EUR","purchaseCurrencyRate":1.1401}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lot = try decoder.decode(PurchaseLot.self, from: Data(json.utf8))
        #expect(lot.purchaseCurrencyRate == 1.1401)
        #expect(lot.needsHistoricalRate)
    }

    @Test func usdLotNeedsNoRate() {
        let lot = PurchaseLot(date: Date(), quantity: 1, price: 100)
        #expect(!lot.needsHistoricalRate)
    }
}
