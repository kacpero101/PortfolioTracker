//
//  PurchaseLotMigrationTests.swift
//  PortfolioTrackerTests
//
//  Zgodność wsteczna assets.json: aliasy klas aktywów, migracja płaskich aktywów do pozycji
//  z transzami, scalanie zakupów tego samego instrumentu i odporność na pojedyncze błędne elementy.
//

import Foundation
import Testing
@testable import PortfolioTracker

@MainActor
struct PurchaseLotMigrationTests {

    /// Plik w kształcie prawdziwego assets.json użytkownika (stary format, dwa zakupy BTC).
    private let realLegacyFile = """
    [{"bondSeries":"EDO0936","id":"A22EAFEA-E3C8-4EA1-BD56-6141F7576D31","name":"Obligacje EDO","purchaseCurrency":"PLN","purchaseCurrencyRate":0.2623,"purchaseDate":"2026-09-27T08:21:15Z","purchasePrice":100,"quantity":3,"type":"Obligacje"},
     {"fetchedPrice":84794.01,"id":"3CE713C9-C1CD-4733-901C-6C8504BD0CA0","lastPriceUpdate":"2026-09-27T08:27:26Z","name":"BTC","purchaseCurrency":"EUR","purchaseCurrencyRate":1.1401,"purchaseDate":"2026-09-27T08:23:03Z","purchasePrice":68000,"quantity":0.00677862,"ticker":"BTC","type":"Kryptowaluty"},
     {"fetchedPrice":84794.01,"id":"22E92C31-240E-4447-A655-595E632AD21E","lastPriceUpdate":"2026-09-27T08:27:26Z","name":"BTC","purchaseCurrency":"EUR","purchaseCurrencyRate":1.1401,"purchaseDate":"2026-09-27T08:24:57Z","purchasePrice":68000,"quantity":0.00041344,"ticker":"BTC","type":"Kryptowaluty"}]
    """

    private func decode(_ json: String) throws -> PortfolioStore.DecodedAssets {
        try PortfolioStore.decodeAssets(from: Data(json.utf8))
    }

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - A. Aliasy AssetType

    @Test(arguments: [
        ("Kryptowaluta", AssetType.crypto), ("Kryptowaluty", .crypto), ("kryptowaluty", .crypto),
        ("Obligacja", .bond), ("Obligacje", .bond), ("obligacje", .bond),
        ("Akcja", .stock), ("akcje", .stock), ("AKCJE", .stock),
        ("Gotowka", .cash), ("Gotówka", .cash), ("gotówka", .cash),
        ("Zloto", .gold), ("złoto", .gold), ("srebro", .silver), ("ETF", .etf), ("etf", .etf)
    ])
    func decodesCurrentAndLegacyTypeNames(raw: String, expected: AssetType) throws {
        let decoded = try JSONDecoder().decode([AssetType].self, from: Data("[\"\(raw)\"]".utf8))
        #expect(decoded == [expected])
    }

    @Test func encodesCurrentRawValues() throws {
        let data = try JSONEncoder().encode([AssetType.crypto, .bond, .cash])
        #expect(String(decoding: data, as: UTF8.self) == #"["Kryptowaluty","Obligacje","Gotówka"]"#)
    }

    @Test func rejectsUnknownTypeName() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([AssetType].self, from: Data(#"["Nieruchomości"]"#.utf8))
        }
    }

    @Test func legacySingularTypeNamesNoLongerWipeThePortfolio() throws {
        // Dokładnie to wcześniej kończyło się plikiem *.unreadable-*.json i pustym portfelem.
        let json = """
        [{"id":"A22EAFEA-E3C8-4EA1-BD56-6141F7576D31","name":"EDO","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":100,"quantity":3,"type":"Obligacja"},
         {"id":"3CE713C9-C1CD-4733-901C-6C8504BD0CA0","name":"BTC","ticker":"BTC","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":68000,"quantity":0.1,"type":"Kryptowaluta"}]
        """
        let result = try decode(json)
        #expect(result.skipped.isEmpty)
        #expect(result.assets.map(\.type) == [.bond, .crypto])
    }

    // MARK: - A. Odporność na pojedyncze błędne elementy

    @Test func skipsOnlyTheUnreadableElement() throws {
        let json = """
        [{"id":"3CE713C9-C1CD-4733-901C-6C8504BD0CA0","name":"BTC","ticker":"BTC","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":68000,"quantity":0.1,"type":"Kryptowaluty"},
         {"id":"11111111-1111-1111-1111-111111111111","name":"Dom","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":1,"quantity":1,"type":"Nieruchomości"},
         {"name":"Bez daty","purchasePrice":1,"quantity":1,"type":"Akcje"},
         {"id":"22222222-2222-2222-2222-222222222222","name":"Gotówka","currency":"PLN","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":1,"quantity":500,"type":"Gotówka"}]
        """
        let result = try decode(json)
        #expect(result.assets.count == 2)
        #expect(result.skipped.count == 2)
        #expect(result.assets.map(\.name) == ["BTC", "Gotówka"])
    }

    @Test func nonArrayFileStillThrows() {
        #expect(throws: (any Error).self) {
            try PortfolioStore.decodeAssets(from: Data(#"{"not":"an array"}"#.utf8))
        }
    }

    // MARK: - C. Migracja do transz

    @Test func migratesRealLegacyFileIntoTwoPositions() throws {
        let result = try decode(realLegacyFile)
        #expect(result.migrated)
        #expect(result.skipped.isEmpty)
        #expect(result.assets.count == 2)

        let bond = try #require(result.assets.first { $0.type == .bond })
        #expect(bond.bondSeries == "EDO0936")
        #expect(bond.name == "Obligacje EDO")
        #expect(bond.lots.count == 1)
        let bondLot = try #require(bond.lots.first)
        #expect(bondLot.id == UUID(uuidString: "A22EAFEA-E3C8-4EA1-BD56-6141F7576D31"))
        #expect(bondLot.quantity == 3)
        #expect(bondLot.price == 100)
        #expect(bondLot.purchaseCurrency == "PLN")
        #expect(bondLot.purchaseCurrencyRate == 0.2623)

        let btc = try #require(result.assets.first { $0.type == .crypto })
        #expect(btc.ticker == "BTC")
        #expect(btc.lots.count == 2)
        #expect(isClose(btc.quantity, 0.00719206))
        #expect(btc.lots.map(\.id) == [
            UUID(uuidString: "3CE713C9-C1CD-4733-901C-6C8504BD0CA0")!,
            UUID(uuidString: "22E92C31-240E-4447-A655-595E632AD21E")!
        ])
        #expect(btc.lots.allSatisfy { $0.price == 68000 && $0.purchaseCurrency == "EUR" && $0.purchaseCurrencyRate == 1.1401 })
        #expect(btc.fetchedPrice == 84794.01)
        #expect(btc.lots.map(\.note) == [nil, nil])
    }

    @Test func migrationIsLosslessForValuation() throws {
        let result = try decode(realLegacyFile)
        let btc = try #require(result.assets.first { $0.type == .crypto })
        // Koszt = suma kosztów obu dawnych aktywów; wartość = łączna ilość × cena.
        let expectedCost = (0.00677862 + 0.00041344) * 68000 * 1.1401
        #expect(isClose(btc.costBasis, expectedCost, tolerance: 1e-6))
        #expect(isClose(btc.currentValue, 0.00719206 * 84794.01, tolerance: 1e-6))
        #expect(isClose(btc.averagePurchasePriceUSD, 68000 * 1.1401, tolerance: 1e-6))
        #expect(btc.averagePurchasePriceInCommonCurrency.map { isClose($0, 68000, tolerance: 1e-6) } == true)
    }

    @Test func bondValuationIsPlainPLNToUSDConversion() throws {
        let result = try decode(realLegacyFile)
        let bond = try #require(result.assets.first { $0.type == .bond })
        // 3 × 100 PLN × 0,2623 USD/PLN = 78,69 USD - bez ceny ręcznej wartość = koszt.
        #expect(isClose(bond.currentValue, 78.69, tolerance: 1e-9))
        #expect(isClose(bond.costBasis, 78.69, tolerance: 1e-9))
        #expect(bond.profitLoss == 0)
    }

    @Test func migratedFileRoundTripsWithoutChanges() throws {
        let migrated = try decode(realLegacyFile).assets
        let data = try JSONEncoder.iso8601.encode(migrated)
        let again = try PortfolioStore.decodeAssets(from: data)
        #expect(again.assets == migrated)
        #expect(again.migrated == false)
        // Nowy format nie zapisuje już płaskich pól zakupu.
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"lots\""))
        #expect(!text.contains("\"purchaseDate\""))
    }

    // MARK: - C. Tożsamość pozycji

    @Test func cryptoTickerWithUsdSuffixIsTheSameInstrument() {
        let a = Asset(name: "BTC", ticker: "BTC", type: .crypto, quantity: 1, purchasePrice: 1, purchaseDate: Date())
        let b = Asset(name: "Bitcoin", ticker: " btc-usd ", type: .crypto, quantity: 1, purchasePrice: 1, purchaseDate: Date())
        #expect(a.identityKey == b.identityKey)
        let merged = Asset.mergedByIdentity([a, b])
        #expect(merged.count == 1)
        // Inna nazwa scalanej pozycji zostaje zachowana w notatce transzy.
        #expect(merged[0].lots.contains { $0.note == "Bitcoin" })
    }

    @Test func differentBondSeriesStaySeparate() {
        var a = Asset(name: "EDO", ticker: nil, type: .bond, quantity: 1, purchasePrice: 100, purchaseDate: Date())
        a.bondSeries = "EDO0936"
        var b = a
        b.id = UUID()
        b.bondSeries = "EDO0433"
        var c = a
        c.id = UUID()
        c.lots = [PurchaseLot(date: Date(), quantity: 2, price: 100)]
        let merged = Asset.mergedByIdentity([a, b, c])
        #expect(merged.count == 2)
        #expect(merged.first { $0.bondSeries == "EDO0936" }?.lots.count == 2)
    }

    @Test func cashIsGroupedByCurrencyAndStocksByTicker() {
        var pln = Asset(name: "Konto", ticker: nil, type: .cash, quantity: 100, purchasePrice: 1, purchaseDate: Date())
        pln.currency = "PLN"
        var pln2 = Asset(name: "Skarbonka", ticker: nil, type: .cash, quantity: 50, purchasePrice: 1, purchaseDate: Date())
        pln2.currency = "pln"
        var eur = Asset(name: "Konto EUR", ticker: nil, type: .cash, quantity: 10, purchasePrice: 1, purchaseDate: Date())
        eur.currency = "EUR"
        let aapl = Asset(name: "Apple", ticker: "aapl", type: .stock, quantity: 1, purchasePrice: 1, purchaseDate: Date())
        let aaplETF = Asset(name: "Apple", ticker: "AAPL", type: .etf, quantity: 1, purchasePrice: 1, purchaseDate: Date())
        let merged = Asset.mergedByIdentity([pln, pln2, eur, aapl, aaplETF])
        #expect(merged.count == 4)
        #expect(merged.first { $0.currency == "PLN" }?.quantity == 150)
    }
}
