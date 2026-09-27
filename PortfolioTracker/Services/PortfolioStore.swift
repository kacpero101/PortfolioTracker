//
//  PortfolioStore.swift
//  PortfolioTracker
//
//  Centralne "źródło prawdy" dla całej aplikacji.
//  - Trzyma listę aktywów i historię wartości portfela.
//  - Zapisuje/wczytuje dane lokalnie jako pliki JSON (ApplicationSupport).
//  - Odpowiada za odświeżanie cen i wyliczanie podsumowań.
//
//  Jest to ObservableObject, więc widoki SwiftUI automatycznie
//  odświeżają się, gdy zmienią się @Published właściwości.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class PortfolioStore: ObservableObject {

    @Published private(set) var assets: [Asset] = []
    @Published private(set) var history: [PortfolioSnapshot] = []

    @Published var isRefreshing: Bool = false
    /// Lista błędów z ostatniego odświeżania, np. "AAPL: brak danych".
    @Published var lastRefreshErrors: [String] = []
    @Published var lastRefreshDate: Date?

    /// Ustawiane, gdy ktoś poprosi o odświeżenie w trakcie trwającego odświeżania.
    private var refreshRequestedWhileRunning = false

    /// Czy odświeżenie przy starcie aplikacji zostało już uruchomione.
    private var didRefreshOnLaunch = false

    // MARK: - Ścieżki plików

    private let assetsFileURL: URL
    private let historyFileURL: URL

    init() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupportDir.appendingPathComponent("PortfolioTracker", isDirectory: true)

        // Tworzymy folder aplikacji w Application Support, jeśli jeszcze nie istnieje.
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.assetsFileURL = appDir.appendingPathComponent("assets.json")
        self.historyFileURL = appDir.appendingPathComponent("history.json")

        load()
    }

    // MARK: - Wyliczenia podsumowania portfela

    var totalValue: Double {
        assets.reduce(0) { $0 + $1.currentValue }
    }

    var totalCostBasis: Double {
        assets.reduce(0) { $0 + $1.costBasis }
    }

    var totalProfitLoss: Double {
        totalValue - totalCostBasis
    }

    var totalProfitLossPercent: Double {
        guard totalCostBasis != 0 else { return 0 }
        return (totalProfitLoss / totalCostBasis) * 100
    }

    /// Alokacja procentowa wartości portfela per klasa aktywów - dane do wykresu kołowego.
    struct AllocationEntry: Identifiable {
        var id: AssetType { type }
        let type: AssetType
        let value: Double
        let percent: Double
    }

    var allocation: [AllocationEntry] {
        let total = totalValue
        let grouped = Dictionary(grouping: assets, by: { $0.type })

        return AssetType.allCases.compactMap { type in
            guard let items = grouped[type] else { return nil }
            let value = items.reduce(0) { $0 + $1.currentValue }
            guard value > 0 else { return nil }
            let percent = total > 0 ? (value / total) * 100 : 0
            return AllocationEntry(type: type, value: value, percent: percent)
        }
    }

    // MARK: - Operacje CRUD na aktywach

    func addAsset(_ asset: Asset) {
        assets.append(asset)
        save()
        if asset.type == .cash || asset.type == .gold || asset.type == .silver || asset.purchaseCurrency != nil {
            Task { await refreshPrices() }
        }
    }

    func updateAsset(_ asset: Asset) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index] = asset
        save()
        if asset.type == .cash || asset.type == .gold || asset.type == .silver || asset.purchaseCurrency != nil {
            Task { await refreshPrices() }
        }
    }

    func deleteAsset(_ asset: Asset) {
        assets.removeAll { $0.id == asset.id }
        save()
    }

    /// Modyfikuje aktywo o podanym id (jeśli nadal istnieje) - bez zapisu na dysk.
    private func updateAsset(id: UUID, _ change: (inout Asset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        change(&assets[index])
    }

    // MARK: - Odświeżanie cen

    /// Odświeża ceny raz po uruchomieniu aplikacji (README: „ceny pobierane przy uruchomieniu”).
    /// Kolejne wywołania (np. z nowego okna) nic nie robią. Jeśli odświeżanie już trwa
    /// (np. po dodaniu aktywa), nie kolejkujemy drugiego - bieżące i tak pobierze aktualne ceny.
    func refreshPricesOnLaunch() async {
        guard !didRefreshOnLaunch else { return }
        didRefreshOnLaunch = true
        guard !assets.isEmpty, !isRefreshing else { return }
        await refreshPrices()
    }

    /// Pobiera aktualne ceny dla wszystkich aktywów, które mają ticker
    /// i należą do klasy z automatycznym pobieraniem ceny (akcje/ETF-y/krypto).
    /// Błąd pojedynczego tickera nie przerywa reszty - jest tylko zbierany do listy błędów.
    ///
    /// UWAGA: między kolejnymi `await` użytkownik może dodać/usunąć aktywo, więc po każdym
    /// pobraniu szukamy pozycji po `id`, a nie po indeksie zapamiętanym przed `await`
    /// (stary indeks mógł wskazywać inne aktywo albo wyjść poza zakres i wywołać crash).
    func refreshPrices() async {
        // Nie uruchamiamy dwóch odświeżań naraz - zamiast tego powtarzamy je po zakończeniu
        // bieżącego (np. gdy użytkownik doda aktywo w trakcie odświeżania).
        guard !isRefreshing else {
            refreshRequestedWhileRunning = true
            return
        }
        isRefreshing = true
        lastRefreshErrors = []
        defer {
            isRefreshing = false
            if refreshRequestedWhileRunning {
                refreshRequestedWhileRunning = false
                Task { await refreshPrices() }
            }
        }

        // Kursy walut do USD pobrane w tym odświeżaniu - każdą parę pobieramy tylko raz
        // (wspólne dla walut notowań, gotówki i walut zakupu).
        var usdRates: [String: Double] = ["USD": 1.0]

        for asset in assets {
            guard asset.type.autoFetchesPrice,
                  let ticker = asset.ticker,
                  !ticker.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }

            let quote: Quote
            do {
                quote = try await PriceService.fetchQuote(ticker: ticker, type: asset.type)
            } catch {
                lastRefreshErrors.append("\(asset.name) (\(ticker)): \(error.localizedDescription)")
                continue
            }

            // Yahoo podaje cenę w walucie notowania (np. PLN dla CDR.WA, GBp dla części LSE),
            // a aplikacja liczy wszystko w USD - przeliczamy, zanim zapiszemy cenę.
            if let code = QuoteCurrency.requiredRateCurrency(for: quote.currency) {
                do {
                    _ = try await usdRate(for: code, cache: &usdRates)
                } catch {
                    lastRefreshErrors.append(
                        "\(asset.name) (\(ticker)): brak kursu \(code)/USD - \(error.localizedDescription)"
                    )
                    continue
                }
            }
            guard let usdPrice = QuoteCurrency.priceInUSD(
                price: quote.price, currency: quote.currency, usdRates: usdRates
            ) else { continue }

            updateAsset(id: asset.id) {
                $0.fetchedPrice = usdPrice
                $0.lastPriceUpdate = Date()
            }
        }

        // Pobierz kursy walut dla aktywów typu gotówka.
        for asset in assets where asset.type == .cash {
            let code = (asset.currency ?? "USD").uppercased()
            if code == "USD" {
                updateAsset(id: asset.id) {
                    $0.fetchedPrice = 1.0
                    $0.lastPriceUpdate = Date()
                }
                continue
            }
            do {
                let rate = try await usdRate(for: code, cache: &usdRates)
                updateAsset(id: asset.id) {
                    $0.fetchedPrice = rate
                    $0.lastPriceUpdate = Date()
                }
            } catch {
                lastRefreshErrors.append("\(asset.name) (\(code)/USD): \(error.localizedDescription)")
            }
        }

        // Pobierz kursy walut zakupu dla aktywów z purchaseCurrency inną niż USD.
        let purchaseCurrencies = Set(assets.compactMap { asset -> String? in
            guard asset.type != .cash,
                  let code = asset.purchaseCurrency,
                  !code.isEmpty else { return nil }
            return code.uppercased()
        })
        for code in purchaseCurrencies {
            do {
                let rate = try await usdRate(for: code, cache: &usdRates)
                for index in assets.indices where assets[index].purchaseCurrency?.uppercased() == code {
                    assets[index].purchaseCurrencyRate = rate
                }
            } catch {
                lastRefreshErrors.append("Kurs zakupu \(code)/USD: \(error.localizedDescription)")
            }
        }

        // Pobierz cenę złota (GC=F) raz i przypisz do wszystkich aktywów złota.
        if assets.contains(where: { $0.type == .gold }) {
            do {
                let goldPrice = try await PriceService.fetchPrice(ticker: "GC=F", type: .stock)
                for index in assets.indices where assets[index].type == .gold {
                    assets[index].fetchedPrice = goldPrice
                    assets[index].lastPriceUpdate = Date()
                }
            } catch {
                lastRefreshErrors.append("Złoto (GC=F): \(error.localizedDescription)")
            }
        }

        // Pobierz cenę srebra (SI=F) raz i przypisz do wszystkich aktywów srebra.
        if assets.contains(where: { $0.type == .silver }) {
            do {
                let silverPrice = try await PriceService.fetchPrice(ticker: "SI=F", type: .stock)
                for index in assets.indices where assets[index].type == .silver {
                    assets[index].fetchedPrice = silverPrice
                    assets[index].lastPriceUpdate = Date()
                }
            } catch {
                lastRefreshErrors.append("Srebro (SI=F): \(error.localizedDescription)")
            }
        }

        lastRefreshDate = Date()
        save()
        recordSnapshot()
    }

    /// Kurs waluty do USD (1 jednostka = x USD) - z `cache` albo pobrany przez `PriceService`.
    private func usdRate(for code: String, cache: inout [String: Double]) async throws -> Double {
        let code = code.uppercased()
        if let cached = cache[code] { return cached }
        let rate = try await PriceService.fetchExchangeRate(from: code)
        cache[code] = rate
        return rate
    }

    // MARK: - Historia wartości portfela

    /// Zapisuje bieżącą wartość portfela jako punkt na wykresie.
    /// Jeśli dzisiejszy snapshot już istnieje, aktualizujemy go zamiast dodawać duplikat.
    func recordSnapshot() {
        let calendar = Calendar.current
        let today = Date()

        if let index = history.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            history[index].totalValue = totalValue
        } else {
            history.append(PortfolioSnapshot(date: today, totalValue: totalValue))
        }

        history.sort { $0.date < $1.date }
        saveHistory()
    }

    // MARK: - Zapis / odczyt z dysku (JSON)

    private func save() {
        saveAssets()
    }

    private func saveAssets() {
        do {
            let data = try JSONEncoder.iso8601.encode(assets)
            try data.write(to: assetsFileURL, options: .atomic)
        } catch {
            print("Błąd zapisu assets.json: \(error)")
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder.iso8601.encode(history)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("Błąd zapisu history.json: \(error)")
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: assetsFileURL) {
            do {
                self.assets = try JSONDecoder.iso8601.decode([Asset].self, from: data)
            } catch {
                // Wcześniej błąd dekodowania był cicho ignorowany, a przy następnym zapisie
                // pusta lista nadpisywała plik - czyli cały portfel przepadał bez śladu.
                print("Błąd odczytu assets.json: \(error)")
                backUpUnreadableFile(assetsFileURL)
            }
        }
        if let data = try? Data(contentsOf: historyFileURL) {
            do {
                self.history = try JSONDecoder.iso8601.decode([PortfolioSnapshot].self, from: data)
            } catch {
                print("Błąd odczytu history.json: \(error)")
                backUpUnreadableFile(historyFileURL)
            }
        }
    }

    /// Kopiuje nieczytelny plik obok oryginału (np. assets.unreadable-2026-09-27T08-30-00Z.json),
    /// żeby nie został nadpisany przy najbliższym zapisie i dało się odzyskać dane.
    private func backUpUnreadableFile(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("unreadable-\(stamp)")
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            print("Zapisano kopię nieczytelnego pliku: \(backupURL.path)")
        } catch {
            print("Nie udało się zapisać kopii \(url.lastPathComponent): \(error)")
        }
    }
}

// MARK: - Pomocnicze koder/dekoder z formatem daty ISO 8601

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
