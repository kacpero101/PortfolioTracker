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

    func deleteAssets(at offsets: IndexSet) {
        assets.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Odświeżanie cen

    /// Pobiera aktualne ceny dla wszystkich aktywów, które mają ticker
    /// i należą do klasy z automatycznym pobieraniem ceny (akcje/ETF-y/krypto).
    /// Błąd pojedynczego tickera nie przerywa reszty - jest tylko zbierany do listy błędów.
    func refreshPrices() async {
        isRefreshing = true
        lastRefreshErrors = []
        defer { isRefreshing = false }

        for index in assets.indices {
            let asset = assets[index]
            guard asset.type.autoFetchesPrice,
                  let ticker = asset.ticker,
                  !ticker.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }

            do {
                let price = try await PriceService.fetchPrice(ticker: ticker, type: asset.type)
                assets[index].fetchedPrice = price
                assets[index].lastPriceUpdate = Date()
            } catch {
                lastRefreshErrors.append("\(asset.name) (\(ticker)): \(error.localizedDescription)")
            }
        }

        // Pobierz kursy walut dla aktywów typu gotówka.
        for index in assets.indices {
            let asset = assets[index]
            guard asset.type == .cash else { continue }
            let code = (asset.currency ?? "USD").uppercased()
            if code == "USD" {
                assets[index].fetchedPrice = 1.0
                assets[index].lastPriceUpdate = Date()
                continue
            }
            do {
                let rate = try await PriceService.fetchExchangeRate(from: code)
                assets[index].fetchedPrice = rate
                assets[index].lastPriceUpdate = Date()
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
                let rate = try await PriceService.fetchExchangeRate(from: code)
                for index in assets.indices where assets[index].purchaseCurrency?.uppercased() == code {
                    assets[index].purchaseCurrencyRate = rate
                }
            } catch {
                lastRefreshErrors.append("Kurs zakupu \(code)/USD: \(error.localizedDescription)")
            }
        }

        // Pobierz cenę złota (GC=F) raz i przypisz do wszystkich aktywów złota.
        let goldIndices = assets.indices.filter { assets[$0].type == .gold }
        if !goldIndices.isEmpty {
            do {
                let goldPrice = try await PriceService.fetchPrice(ticker: "GC=F", type: .stock)
                for index in goldIndices {
                    assets[index].fetchedPrice = goldPrice
                    assets[index].lastPriceUpdate = Date()
                }
            } catch {
                lastRefreshErrors.append("Złoto (GC=F): \(error.localizedDescription)")
            }
        }

        // Pobierz cenę srebra (SI=F) raz i przypisz do wszystkich aktywów srebra.
        let silverIndices = assets.indices.filter { assets[$0].type == .silver }
        if !silverIndices.isEmpty {
            do {
                let silverPrice = try await PriceService.fetchPrice(ticker: "SI=F", type: .stock)
                for index in silverIndices {
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
        if let data = try? Data(contentsOf: assetsFileURL),
           let decoded = try? JSONDecoder.iso8601.decode([Asset].self, from: data) {
            self.assets = decoded
        }
        if let data = try? Data(contentsOf: historyFileURL),
           let decoded = try? JSONDecoder.iso8601.decode([PortfolioSnapshot].self, from: data) {
            self.history = decoded
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
