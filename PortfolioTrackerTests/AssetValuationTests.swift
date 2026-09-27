//
//  AssetValuationTests.swift
//  PortfolioTrackerTests
//
//  Wycena pozycji z ceną ręczną oraz domyślne kolory klas aktywów.
//

import Foundation
import Testing
@testable import PortfolioTracker

@MainActor
struct AssetValuationTests {

    @Test func manualStockPriceIsInPurchaseCurrencyAndUsedWithoutFetchedPrice() {
        var asset = Asset(name: "CD Projekt", ticker: "CDR.WA", type: .stock, quantity: 2,
                          purchasePrice: 200, purchaseDate: Date())
        asset.purchaseCurrency = "PLN"
        asset.purchaseCurrencyRate = 0.25
        asset.manualCurrentPrice = 240
        // 240 PLN × 0,25 = 60 USD za akcję - tak samo jak koszt nabycia i obligacje.
        #expect(asset.currentPrice == 60)
        #expect(asset.currentValue == 120)
        #expect(asset.costBasis == 100)
    }

    @Test func fetchedPriceTakesPrecedenceOverManualPrice() {
        var asset = Asset(name: "Srebro", ticker: nil, type: .silver, quantity: 1,
                          purchasePrice: 25, purchaseDate: Date())
        asset.manualCurrentPrice = 30
        #expect(asset.currentPrice == 30)
        asset.fetchedPrice = 32
        #expect(asset.currentPrice == 32)
    }

    @Test func everyAssetTypeHasDistinctDefaultColor() {
        let indices = AssetType.allCases.map { AssetColorStore.defaultIndices[$0] }
        #expect(!indices.contains(nil))
        #expect(Set(indices.compactMap { $0 }).count == AssetType.allCases.count)
        #expect(indices.compactMap { $0 }.allSatisfy { AssetColorStore.palette.indices.contains($0) })
    }
}
