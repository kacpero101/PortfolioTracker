//
//  PortfolioStore.swift
//  PortfolioTracker
//
//  Centralne "źródło prawdy" dla całej aplikacji.
//  - Trzyma listę pozycji (z transzami zakupu) i historię wartości portfela.
//  - Zapisuje/wczytuje dane lokalnie jako pliki JSON (ApplicationSupport).
//  - Odpowiada za odświeżanie cen i wyliczanie podsumowań.
//
//  Jest to ObservableObject, więc widoki SwiftUI automatycznie
//  odświeżają się, gdy zmienią się @Published właściwości.
//

import Foundation
import Combine
import SwiftUI

/// Źródło oprocentowania serii EDO - w aplikacji `BondRateService`, w testach atrapa.
protocol BondRateProviding: AnyObject {
    func rate(for series: String, forceRefresh: Bool) async throws -> EDOSeriesRate
}

extension BondRateService: BondRateProviding {}

@MainActor
final class PortfolioStore: ObservableObject {

    @Published private(set) var assets: [Asset] = []
    @Published private(set) var history: [PortfolioSnapshot] = []

    @Published var isRefreshing: Bool = false
    /// Lista błędów z ostatniego odświeżania, np. "AAPL: brak danych".
    @Published var lastRefreshErrors: [String] = []
    @Published var lastRefreshDate: Date?

    /// Ostrzeżenia z wczytywania danych (np. pominięte, nieczytelne pozycje).
    @Published private(set) var loadWarnings: [String] = []

    /// Pozycje obligacji, dla których automatyczne pobranie oprocentowania się nie udało (id -> komunikat).
    @Published private(set) var bondRateFetchFailures: [UUID: String] = [:]

    /// Ustawiane, gdy ktoś poprosi o odświeżenie w trakcie trwającego odświeżania.
    private var refreshRequestedWhileRunning = false

    /// Czy odświeżenie przy starcie aplikacji zostało już uruchomione.
    private var didRefreshOnLaunch = false

    private var isFetchingBondRates = false

    /// Czy po zmianie pozycji automatycznie pobierać ceny/kursy/oprocentowanie (w testach wyłączane).
    var automaticFetchingEnabled = true

    private let bondRates: BondRateProviding

    // MARK: - Ścieżki plików

    private let assetsFileURL: URL
    private let historyFileURL: URL

    /// - Parameters:
    ///   - directory: folder z plikami danych; domyślnie Application Support/PortfolioTracker.
    ///   - bondRates: źródło oprocentowania obligacji; domyślnie `BondRateService.shared`.
    init(directory: URL? = nil, bondRates: BondRateProviding? = nil) {
        let fileManager = FileManager.default
        let appDir = directory ?? Self.defaultDirectory()

        // Tworzymy folder aplikacji, jeśli jeszcze nie istnieje.
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.assetsFileURL = appDir.appendingPathComponent("assets.json")
        self.historyFileURL = appDir.appendingPathComponent("history.json")
        self.bondRates = bondRates ?? BondRateService.shared

        load()
    }

    /// Application Support/PortfolioTracker. Gdy aplikacja działa jako host testów,
    /// używamy folderu tymczasowego, żeby testy nigdy nie czytały ani nie nadpisywały prawdziwego portfela.
    static func defaultDirectory() -> URL {
        if isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("PortfolioTracker-TestHost-\(ProcessInfo.processInfo.processIdentifier)",
                                        isDirectory: true)
        }
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportDir.appendingPathComponent("PortfolioTracker", isDirectory: true)
    }

    /// Czy proces jest hostem testów jednostkowych (XCTest / Swift Testing uruchamiane przez Xcode).
    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
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

    // MARK: - Operacje na pozycjach i transzach

    /// Wynik dodania zakupu: nowa pozycja albo transza dopisana do istniejącej.
    enum AddResult: Equatable {
        case createdPosition(Asset)
        case addedLot(to: Asset)
    }

    /// Istniejąca pozycja dla tego samego instrumentu (typ + ticker / waluta / seria).
    func existingPosition(matching asset: Asset) -> Asset? {
        let key = asset.identityKey
        return assets.first { $0.identityKey == key && $0.id != asset.id }
    }

    /// Dodaje zakup. Jeśli instrument jest już w portfelu, transze trafiają do istniejącej pozycji.
    @discardableResult
    func addPurchase(_ asset: Asset) -> AddResult {
        let result: AddResult
        if let index = assets.firstIndex(where: { $0.identityKey == asset.identityKey }) {
            var position = assets[index]
            position.absorb(asset)
            // Nowo podana cena ręczna zastępuje poprzednią (użytkownik wpisał ją świadomie teraz).
            if let manual = asset.manualCurrentPrice {
                position.manualCurrentPrice = manual
                position.manualPriceCurrency = asset.manualPriceCurrency
                position.manualPriceCurrencyRate = asset.manualPriceCurrencyRate
            }
            assets[index] = position
            result = .addedLot(to: position)
        } else {
            var position = asset
            position.lots.sort { $0.date < $1.date }
            assets.append(position)
            result = .createdPosition(position)
        }
        let affected: Asset
        switch result {
        case .createdPosition(let a), .addedLot(let a): affected = a
        }
        assetsDidChange(affected: affected)
        return result
    }

    /// Zapisuje zmienione pola pozycji (i jej transze). Jeśli po zmianie (np. tickera)
    /// pozycja pokrywa się z inną, obie są scalane.
    func updatePosition(_ asset: Asset) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        if asset.lots.isEmpty {
            assets.remove(at: index)
        } else {
            assets[index] = asset
            assets = Asset.mergedByIdentity(assets)
        }
        assetsDidChange(affected: asset)
    }

    func deletePosition(_ asset: Asset) {
        assets.removeAll { $0.id == asset.id }
        bondRateFetchFailures[asset.id] = nil
        assetsDidChange(affected: nil)
    }

    /// Zmienia transzę `lot` w pozycji `positionID`.
    func updateLot(_ lot: PurchaseLot, inPosition positionID: UUID) {
        guard let index = assets.firstIndex(where: { $0.id == positionID }),
              let lotIndex = assets[index].lots.firstIndex(where: { $0.id == lot.id }) else { return }
        assets[index].lots[lotIndex] = lot
        assets[index].lots.sort { $0.date < $1.date }
        assetsDidChange(affected: assets[index])
    }

    /// Usuwa transzę. Usunięcie ostatniej transzy usuwa całą pozycję.
    func deleteLot(id lotID: UUID, fromPosition positionID: UUID) {
        guard let index = assets.firstIndex(where: { $0.id == positionID }) else { return }
        assets[index].lots.removeAll { $0.id == lotID }
        if assets[index].lots.isEmpty {
            bondRateFetchFailures[positionID] = nil
            assets.remove(at: index)
            assetsDidChange(affected: nil)
        } else {
            assetsDidChange(affected: assets[index])
        }
    }

    /// Po każdej zmianie: zapis, aktualizacja dzisiejszego punktu historii, a w razie potrzeby
    /// pobranie brakujących kursów/cen i oprocentowania obligacji.
    private func assetsDidChange(affected: Asset?) {
        save()
        recordSnapshot()
        guard automaticFetchingEnabled, let affected else { return }
        if needsPriceRefresh(affected) {
            Task { await refreshPrices() }
        } else if affected.needsBondRateFetch {
            Task { await fetchMissingBondRates() }
        }
    }

    private func needsPriceRefresh(_ asset: Asset) -> Bool {
        if asset.type == .cash || asset.type == .gold || asset.type == .silver { return true }
        if asset.type.autoFetchesPrice && asset.fetchedPrice == nil { return true }
        let usesForeignCurrency = asset.lots.contains { $0.displayCurrency != "USD" }
            || (asset.manualPriceCurrency.map { $0.uppercased() != "USD" } ?? false)
        return usesForeignCurrency
    }

    /// Modyfikuje aktywo o podanym id (jeśli nadal istnieje) - bez zapisu na dysk.
    private func updateAsset(id: UUID, _ change: (inout Asset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        change(&assets[index])
    }

    // MARK: - Oprocentowanie obligacji

    /// Pobiera (z pamięci podręcznej albo obligacjeskarbowe.pl) oprocentowanie dla obligacji,
    /// które mają serię, ale brakuje im stawki pierwszego roku lub marży. Uzupełnia tylko
    /// brakujące pola - wartości wpisane ręcznie nie są nadpisywane. Błędy trafiają
    /// do `lastRefreshErrors` i `bondRateFetchFailures`.
    func fetchMissingBondRates() async {
        guard !isFetchingBondRates else { return }
        isFetchingBondRates = true
        defer { isFetchingBondRates = false }

        let targets = assets.filter(\.needsBondRateFetch)
        var changed = false
        for target in targets {
            guard let series = target.bondSeries.flatMap(EDOSeries.normalize) else { continue }
            do {
                let result = try await bondRates.rate(for: series, forceRefresh: false)
                updateAsset(id: target.id) { asset in
                    if asset.bondFirstYearRate == nil { asset.bondFirstYearRate = result.firstYearRate }
                    if asset.bondMargin == nil, let margin = result.margin { asset.bondMargin = margin }
                    asset.bondRateFetchDate = result.fetchedAt
                }
                bondRateFetchFailures[target.id] = nil
                changed = true
                if result.margin == nil && target.bondMargin == nil {
                    lastRefreshErrors.append(
                        "\(target.name) (\(series)): strona nie podaje marży - wpisz ją ręcznie w edycji pozycji."
                    )
                }
            } catch {
                let message = error.localizedDescription
                bondRateFetchFailures[target.id] = message
                lastRefreshErrors.append("\(target.name) (\(series)): oprocentowanie - \(message)")
            }
        }
        if changed { save() }
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

    /// Pobiera aktualne ceny dla wszystkich pozycji, kursy walut i brakujące oprocentowanie obligacji.
    /// Błąd pojedynczego tickera nie przerywa reszty - jest tylko zbierany do listy błędów.
    ///
    /// UWAGA: między kolejnymi `await` użytkownik może dodać/usunąć pozycję, więc po każdym
    /// pobraniu szukamy pozycji po `id`, a nie po indeksie zapamiętanym przed `await`.
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

        // Obligacje z serią, ale bez oprocentowania (np. zapisane bez kliknięcia „Pobierz oprocentowanie”).
        await fetchMissingBondRates()

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

        // Pobierz kursy walut dla pozycji typu gotówka.
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

        // Kurs zakupu każdej transzy w obcej walucie to kurs z dnia zakupu - pobieramy go raz,
        // potem jest stały (koszt zakupu nie zmienia się razem z bieżącym kursem).
        var historicalRates: [String: Double] = [:]
        for asset in assets where asset.type != .cash {
            for lot in asset.lots where lot.needsHistoricalRate {
                guard let code = lot.purchaseCurrency?.uppercased() else { continue }
                let cacheKey = "\(code)|\(Int(lot.date.timeIntervalSince1970 / 86_400))"
                do {
                    let rate: Double
                    if let cached = historicalRates[cacheKey] {
                        rate = cached
                    } else {
                        rate = try await PriceService.fetchHistoricalExchangeRate(from: code, on: lot.date)
                        historicalRates[cacheKey] = rate
                    }
                    updateAsset(id: asset.id) { Self.setPurchaseRate(rate, historical: true, lotID: lot.id, in: &$0) }
                } catch {
                    lastRefreshErrors.append(
                        "\(asset.name): kurs \(code)/USD z dnia zakupu - \(error.localizedDescription)"
                    )
                    // Bez żadnego kursu koszt byłby liczony 1:1 - tymczasowo bierzemy bieżący kurs
                    // (bez oznaczenia jako historyczny, więc przy kolejnym odświeżeniu spróbujemy znowu).
                    if lot.purchaseCurrencyRate == nil,
                       let current = try? await usdRate(for: code, cache: &usdRates) {
                        updateAsset(id: asset.id) { Self.setPurchaseRate(current, historical: false, lotID: lot.id, in: &$0) }
                    }
                }
            }
        }

        // Ceny ręczne to wycena na dziś - przeliczamy je po bieżącym kursie.
        for code in Self.manualPriceCurrencies(in: assets) {
            do {
                let rate = try await usdRate(for: code, cache: &usdRates)
                Self.applyManualPrice(rate: rate, forCurrency: code, to: &assets)
            } catch {
                lastRefreshErrors.append("Kurs ceny ręcznej \(code)/USD: \(error.localizedDescription)")
            }
        }

        // Pobierz cenę złota (GC=F) raz i przypisz do wszystkich pozycji złota.
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

        // Pobierz cenę srebra (SI=F) raz i przypisz do wszystkich pozycji srebra.
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

    /// Waluty (poza USD) cen ręcznych - ich bieżące kursy trzeba pobrać.
    static func manualPriceCurrencies(in assets: [Asset]) -> Set<String> {
        var codes = Set<String>()
        for asset in assets where asset.type != .cash {
            if let code = asset.manualPriceCurrency?.uppercased(), !code.isEmpty { codes.insert(code) }
        }
        codes.remove("USD")
        return codes
    }

    /// Ustawia bieżący kurs `code`→USD we wszystkich cenach ręcznych w tej walucie.
    static func applyManualPrice(rate: Double, forCurrency code: String, to assets: inout [Asset]) {
        for index in assets.indices
        where assets[index].type != .cash && assets[index].manualPriceCurrency?.uppercased() == code {
            assets[index].manualPriceCurrencyRate = rate
        }
    }

    /// Zapisuje kurs zakupu w transzy `lotID` pozycji `asset`. Kursu z dnia zakupu
    /// (`historical == true`) nie nadpisujemy już kursem tymczasowym.
    static func setPurchaseRate(_ rate: Double, historical: Bool, lotID: UUID, in asset: inout Asset) {
        guard let index = asset.lots.firstIndex(where: { $0.id == lotID }) else { return }
        if asset.lots[index].purchaseRateIsHistorical == true && !historical { return }
        asset.lots[index].purchaseCurrencyRate = rate
        asset.lots[index].purchaseRateIsHistorical = historical
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
    /// Wywoływane po odświeżeniu cen oraz po każdej zmianie pozycji (dodanie/edycja/usunięcie).
    func recordSnapshot() {
        let calendar = Calendar.current
        let today = Date()

        if let index = history.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            history[index].totalValue = totalValue
            history[index].date = today
        } else {
            history.append(PortfolioSnapshot(date: today, totalValue: totalValue))
        }

        history.sort { $0.date < $1.date }
        saveHistory()
    }

    /// Usuwa całą historię (np. stare, testowe punkty) i zapisuje świeży punkt z bieżącą wartością portfela.
    func clearHistory() {
        history = []
        recordSnapshot()
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

    /// Wynik wczytania assets.json.
    struct DecodedAssets {
        /// Pozycje po migracji i scaleniu transz tego samego instrumentu.
        var assets: [Asset]
        /// Opisy elementów, których nie dało się odczytać (zostały pominięte).
        var skipped: [String]
        /// Czy plik był w starym formacie (bez transz) albo wymagał scalenia pozycji.
        var migrated: Bool
    }

    /// Odczytuje assets.json odpornie na błędy pojedynczych elementów: nieczytelna pozycja
    /// jest pomijana, a pozostałe wczytywane. Stary format (jedno aktywo = jeden zakup) jest
    /// zamieniany na pozycje z transzami, a zakupy tego samego instrumentu - scalane.
    /// Rzuca błąd tylko wtedy, gdy plik w ogóle nie jest tablicą JSON.
    static func decodeAssets(from data: Data) throws -> DecodedAssets {
        let elements = try JSONDecoder.iso8601.decode([LossyDecoded<Asset>].self, from: data)
        var decoded: [Asset] = []
        var skipped: [String] = []
        for (offset, element) in elements.enumerated() {
            switch element.result {
            case .success(let asset):
                decoded.append(asset)
            case .failure(let error):
                skipped.append("element \(offset + 1): \(Self.describe(error))")
            }
        }
        let merged = Asset.mergedByIdentity(decoded)

        // Stary format rozpoznajemy po braku klucza "lots" w którymkolwiek elemencie.
        let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        let hadLegacyElements = raw.contains { $0["lots"] == nil }
        return DecodedAssets(
            assets: merged,
            skipped: skipped,
            migrated: hadLegacyElements || merged.count != decoded.count
        )
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
             DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).filter { Int($0) == nil }.joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path) - \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: assetsFileURL) {
            do {
                let result = try Self.decodeAssets(from: data)
                self.assets = result.assets
                if !result.skipped.isEmpty {
                    // Część pozycji jest nieczytelna - zachowujemy kopię oryginału, zanim
                    // pierwszy zapis nadpisze plik bez tych pozycji.
                    let backup = backUpFile(assetsFileURL, suffix: "unreadable")
                    print("Pominięto nieczytelne pozycje w assets.json: \(result.skipped)")
                    loadWarnings.append(
                        "Pominięto \(result.skipped.count) nieczytelnych pozycji z assets.json"
                        + (backup.map { " (kopia pliku: \($0.lastPathComponent))" } ?? "")
                        + ": " + result.skipped.joined(separator: "; ")
                    )
                } else if result.migrated {
                    // Migracja do formatu z transzami jest bezstratna, ale na wszelki wypadek
                    // zostawiamy kopię pliku w starym formacie.
                    _ = backUpFile(assetsFileURL, suffix: "pre-lots")
                }
            } catch {
                // Plik w ogóle nie jest listą pozycji - zachowujemy kopię i zaczynamy od pustej listy.
                print("Błąd odczytu assets.json: \(error)")
                let backup = backUpFile(assetsFileURL, suffix: "unreadable")
                loadWarnings.append(
                    "Nie udało się odczytać assets.json" + (backup.map { " (kopia: \($0.lastPathComponent))" } ?? "")
                )
            }
        }
        if let data = try? Data(contentsOf: historyFileURL) {
            do {
                self.history = try JSONDecoder.iso8601.decode([PortfolioSnapshot].self, from: data)
            } catch {
                print("Błąd odczytu history.json: \(error)")
                _ = backUpFile(historyFileURL, suffix: "unreadable")
            }
        }
    }

    /// Kopiuje plik obok oryginału (np. assets.unreadable-2026-09-27T08-30-00Z.json),
    /// żeby nie został nadpisany przy najbliższym zapisie i dało się odzyskać dane.
    @discardableResult
    private func backUpFile(_ url: URL, suffix: String) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("\(suffix)-\(stamp)")
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            print("Zapisano kopię pliku: \(backupURL.path)")
            return backupURL
        } catch {
            print("Nie udało się zapisać kopii \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}

/// Element tablicy, którego błąd dekodowania nie przerywa dekodowania całej tablicy.
struct LossyDecoded<Value: Decodable>: Decodable {
    let result: Result<Value, Error>

    init(from decoder: Decoder) throws {
        do {
            result = .success(try Value(from: decoder))
        } catch {
            result = .failure(error)
        }
    }
}

// MARK: - Pomocnicze koder/dekoder z formatem daty ISO 8601

extension JSONEncoder {
    nonisolated static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
