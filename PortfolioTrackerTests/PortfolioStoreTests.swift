//
//  PortfolioStoreTests.swift
//  PortfolioTrackerTests
//
//  Operacje na pozycjach i transzach, wczytywanie starego pliku z dysku, automatyczne
//  pobieranie oprocentowania obligacji i historia - na plikach w folderze tymczasowym.
//

import Foundation
import Testing
@testable import PortfolioTracker

/// Atrapa źródła oprocentowania EDO (bez sieci).
@MainActor
final class MockBondRates: BondRateProviding {
    var rates: [String: EDOSeriesRate] = [:]
    var requested: [String] = []

    func rate(for series: String, forceRefresh: Bool) async throws -> EDOSeriesRate {
        requested.append(series)
        guard let rate = rates[series] else { throw BondRateError.seriesNotFound(series) }
        return rate
    }
}

@MainActor
struct PortfolioStoreTests {

    private let directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PortfolioStoreTests-\(UUID().uuidString)", isDirectory: true)

    private func makeStore(bondRates: MockBondRates? = nil) -> PortfolioStore {
        let store = PortfolioStore(directory: directory, bondRates: bondRates ?? MockBondRates())
        store.automaticFetchingEnabled = false
        return store
    }

    private func btc(quantity: Double, ticker: String = "BTC") -> Asset {
        var asset = Asset(name: "BTC", ticker: ticker, type: .crypto, quantity: quantity,
                          purchasePrice: 60000, purchaseDate: Date())
        asset.fetchedPrice = 80000
        return asset
    }

    // MARK: - Transze

    @Test func addingExistingInstrumentAppendsLot() {
        let store = makeStore()
        let first = store.addPurchase(btc(quantity: 0.5))
        guard case .createdPosition = first else {
            Issue.record("Pierwszy zakup powinien utworzyć pozycję")
            return
        }
        let second = store.addPurchase(btc(quantity: 0.25, ticker: "btc-usd"))
        guard case .addedLot(let position) = second else {
            Issue.record("Drugi zakup powinien trafić do istniejącej pozycji")
            return
        }
        #expect(position.name == "BTC")
        #expect(store.assets.count == 1)
        #expect(store.assets[0].lots.count == 2)
        #expect(store.assets[0].quantity == 0.75)
    }

    @Test func editingAndDeletingLots() throws {
        let store = makeStore()
        store.addPurchase(btc(quantity: 0.5))
        store.addPurchase(btc(quantity: 0.25))
        let position = try #require(store.assets.first)
        var lot = position.lots[1]
        lot.quantity = 1
        lot.note = "korekta"
        store.updateLot(lot, inPosition: position.id)
        #expect(store.assets[0].quantity == 1.5)
        #expect(store.assets[0].lots.contains { $0.note == "korekta" })

        store.deleteLot(id: position.lots[0].id, fromPosition: position.id)
        #expect(store.assets[0].lots.count == 1)
        // Usunięcie ostatniej transzy usuwa pozycję.
        store.deleteLot(id: lot.id, fromPosition: position.id)
        #expect(store.assets.isEmpty)
    }

    @Test func deletingPositionRemovesAllLots() throws {
        let store = makeStore()
        store.addPurchase(btc(quantity: 0.5))
        store.addPurchase(btc(quantity: 0.25))
        store.deletePosition(try #require(store.assets.first))
        #expect(store.assets.isEmpty)
    }

    @Test func changesArePersisted() throws {
        let store = makeStore()
        store.addPurchase(btc(quantity: 0.5))
        store.addPurchase(btc(quantity: 0.25))
        let reloaded = makeStore()
        // Daty w JSON-ie mają dokładność do sekundy, więc porównujemy identyfikatory i ilości.
        #expect(reloaded.assets.map(\.id) == store.assets.map(\.id))
        #expect(reloaded.assets.first?.lots.map(\.id) == store.assets.first?.lots.map(\.id))
        #expect(reloaded.assets.first?.quantity == 0.75)
    }

    @Test func loadsLegacyFileFromDiskAndKeepsBackup() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        [{"id":"3CE713C9-C1CD-4733-901C-6C8504BD0CA0","name":"BTC","ticker":"BTC","purchaseDate":"2026-09-27T08:23:03Z","purchasePrice":68000,"quantity":0.00677862,"type":"Kryptowaluta"},
         {"id":"22E92C31-240E-4447-A655-595E632AD21E","name":"BTC","ticker":"BTC","purchaseDate":"2026-09-27T08:24:57Z","purchasePrice":68000,"quantity":0.00041344,"type":"Kryptowaluty"},
         {"id":"11111111-1111-1111-1111-111111111111","name":"Dom","purchaseDate":"2026-09-01T00:00:00Z","purchasePrice":1,"quantity":1,"type":"Nieruchomości"}]
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("assets.json"))

        let store = makeStore()
        #expect(store.assets.count == 1)
        #expect(store.assets[0].lots.count == 2)
        #expect(store.loadWarnings.count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("assets.unreadable-") })
    }

    // MARK: - B. Oprocentowanie obligacji

    @Test func fetchesMissingBondRateAndKeepsManualValues() async throws {
        let mock = MockBondRates()
        mock.rates["EDO0936"] = EDOSeriesRate(series: "EDO0936", firstYearRate: 5.35, margin: 2.0, fetchedAt: Date())
        let store = makeStore(bondRates: mock)

        var bond = Asset(name: "Obligacje EDO", ticker: nil, type: .bond, quantity: 3, purchasePrice: 100,
                         purchaseDate: Date(), purchaseCurrency: "PLN", purchaseCurrencyRate: 0.2623)
        bond.bondSeries = "EDO0936"
        store.addPurchase(bond)
        #expect(store.assets[0].needsBondRateFetch)

        await store.fetchMissingBondRates()
        #expect(store.assets[0].bondFirstYearRate == 5.35)
        #expect(store.assets[0].bondMargin == 2.0)
        #expect(store.assets[0].currentBondRate == 5.35)
        #expect(store.bondRateFetchFailures.isEmpty)

        // Już uzupełnione - kolejne wywołanie nie pyta serwisu.
        await store.fetchMissingBondRates()
        #expect(mock.requested == ["EDO0936"])
    }

    @Test func bondRateFailureIsReportedNotSilent() async throws {
        let store = makeStore()
        var bond = Asset(name: "EDO", ticker: nil, type: .bond, quantity: 1, purchasePrice: 100, purchaseDate: Date())
        bond.bondSeries = "EDO0999"
        store.addPurchase(bond)
        await store.fetchMissingBondRates()
        #expect(store.assets[0].bondFirstYearRate == nil)
        #expect(store.bondRateFetchFailures[store.assets[0].id] != nil)
        #expect(store.lastRefreshErrors.contains { $0.contains("EDO0999") })
    }

    // MARK: - D. Historia

    @Test func assetChangesUpdateTodaysSnapshot() throws {
        let store = makeStore()
        store.addPurchase(btc(quantity: 0.5))
        #expect(store.history.count == 1)
        #expect(store.history[0].totalValue == 40000)
        store.addPurchase(btc(quantity: 0.5))
        #expect(store.history.count == 1)
        #expect(store.history[0].totalValue == 80000)
        store.deletePosition(try #require(store.assets.first))
        #expect(store.history.last?.totalValue == 0)
    }

    @Test func clearHistoryKeepsOnlyFreshSnapshot() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldHistory = """
        [{"id":"AAAAAAAA-0000-0000-0000-000000000001","date":"2026-09-08T10:00:00Z","totalValue":15112},
         {"id":"AAAAAAAA-0000-0000-0000-000000000002","date":"2026-09-12T10:00:00Z","totalValue":77326}]
        """
        try Data(oldHistory.utf8).write(to: directory.appendingPathComponent("history.json"))
        let store = makeStore()
        #expect(store.history.count == 2)

        store.addPurchase(btc(quantity: 0.5))
        #expect(store.history.count == 3)

        store.clearHistory()
        #expect(store.history.count == 1)
        #expect(store.history[0].totalValue == 40000)
        #expect(Calendar.current.isDateInToday(store.history[0].date))
        #expect(makeStore().history.count == 1)
    }
}

/// Test na żywo z obligacjeskarbowe.pl - tą samą ścieżką co aplikacja (BondRateService).
/// Uruchamiany tylko na żądanie: `TEST_RUNNER_LIVE_NETWORK=1 xcodebuild test ...`.
@MainActor
struct LiveBondRateTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_NETWORK"] == "1"))
    func edo0936FromObligacjeSkarbowe() async throws {
        let suite = "PortfolioTrackerTests.live.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BondRateService(defaults: defaults)
        let rate = try await service.rate(for: "EDO0936", forceRefresh: true)
        #expect(rate.firstYearRate == 5.35)
        #expect(rate.margin == 2.0)
    }
}
