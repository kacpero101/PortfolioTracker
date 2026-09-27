//
//  Asset.swift
//  PortfolioTracker
//
//  Pozycja w portfelu - jeden instrument (np. BTC, akcje Apple, obligacje EDO0936)
//  z listą transz zakupu (`lots`). Ilość, średnia cena i koszt są wyliczane z transz.
//

import Foundation

struct Asset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    /// Własna nazwa pozycji, np. "Apple Inc." albo "Obligacje skarbowe EDO0433"
    var name: String

    /// Ticker giełdowy używany do pobierania ceny (akcje / ETF-y / krypto).
    /// Dla obligacji i gotówki może być pusty.
    var ticker: String?

    var type: AssetType

    /// Transze zakupu (co najmniej jedna w zapisanym portfelu).
    var lots: [PurchaseLot] = []

    /// Waluta gotówki - wypełniana tylko gdy type == .cash.
    var currency: String?

    /// Cena ustawiana ręcznie - używana gdy nie ma ceny pobranej automatycznie.
    /// Podawana w walucie `manualPriceCurrency` (nil = USD).
    var manualCurrentPrice: Double?

    /// Waluta ceny ręcznej (nil = USD).
    var manualPriceCurrency: String?

    /// Bieżący kurs manualPriceCurrency→USD, aktualizowany przy odświeżeniu cen.
    var manualPriceCurrencyRate: Double?

    /// Ostatnia cena pobrana automatycznie (w USD; dla gotówki: kurs waluty do USD).
    var fetchedPrice: Double?

    var lastPriceUpdate: Date?

    // MARK: - Obligacje skarbowe EDO
    //
    // Oprocentowanie jest cechą serii, więc trzymamy je na poziomie pozycji
    // (pozycja obligacji = typ + seria, różne serie to osobne pozycje).

    /// Seria obligacji EDO, np. "EDO0936" (sprzedaż we wrześniu 2026, wykup we wrześniu 2036).
    var bondSeries: String?

    /// Oprocentowanie w pierwszym rocznym okresie odsetkowym, w procentach (np. 5.35).
    var bondFirstYearRate: Double?

    /// Marża ponad inflację obowiązująca od drugiego roku, w procentach (np. 2.00).
    var bondMargin: Double?

    /// Inflacja (CPI r/r) przyjęta dla bieżącego okresu odsetkowego, w procentach - wpisywana ręcznie.
    var bondInflation: Double?

    /// Kiedy oprocentowanie zostało ostatnio pobrane z obligacjeskarbowe.pl (nil = wpisane ręcznie).
    var bondRateFetchDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        ticker: String? = nil,
        type: AssetType,
        lots: [PurchaseLot] = [],
        currency: String? = nil,
        manualCurrentPrice: Double? = nil,
        manualPriceCurrency: String? = nil,
        manualPriceCurrencyRate: Double? = nil,
        fetchedPrice: Double? = nil,
        lastPriceUpdate: Date? = nil,
        bondSeries: String? = nil,
        bondFirstYearRate: Double? = nil,
        bondMargin: Double? = nil,
        bondInflation: Double? = nil,
        bondRateFetchDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.ticker = ticker
        self.type = type
        self.lots = lots
        self.currency = currency
        self.manualCurrentPrice = manualCurrentPrice
        self.manualPriceCurrency = manualPriceCurrency
        self.manualPriceCurrencyRate = manualPriceCurrencyRate
        self.fetchedPrice = fetchedPrice
        self.lastPriceUpdate = lastPriceUpdate
        self.bondSeries = bondSeries
        self.bondFirstYearRate = bondFirstYearRate
        self.bondMargin = bondMargin
        self.bondInflation = bondInflation
        self.bondRateFetchDate = bondRateFetchDate
    }

    /// Wygodny inicjalizator pozycji z jedną transzą (m.in. dla testów i formularza).
    init(
        name: String,
        ticker: String?,
        type: AssetType,
        quantity: Double,
        purchasePrice: Double,
        purchaseDate: Date,
        purchaseCurrency: String? = nil,
        purchaseCurrencyRate: Double? = nil
    ) {
        self.init(name: name, ticker: ticker, type: type, lots: [
            PurchaseLot(date: purchaseDate, quantity: quantity, price: purchasePrice,
                        purchaseCurrency: purchaseCurrency, purchaseCurrencyRate: purchaseCurrencyRate)
        ])
    }

    // MARK: - Wartości wyliczane z transz

    /// Łączna ilość jednostek we wszystkich transzach.
    var quantity: Double {
        lots.reduce(0) { $0 + $1.quantity }
    }

    /// Data pierwszego zakupu (albo nil, gdy pozycja nie ma transz).
    var firstPurchaseDate: Date? {
        lots.map(\.date).min()
    }

    /// Wspólna waluta zakupu wszystkich transz (nil, gdy transze mają różne waluty albo brak transz).
    var commonPurchaseCurrency: String? {
        let codes = Set(lots.map(\.displayCurrency))
        return codes.count == 1 ? codes.first : nil
    }

    /// Średnia ważona cena zakupu w USD.
    var averagePurchasePriceUSD: Double {
        let qty = quantity
        guard qty != 0 else { return 0 }
        return lots.reduce(0) { $0 + $1.costBasisUSD } / qty
    }

    /// Średnia ważona cena zakupu w walucie zakupu - tylko gdy wszystkie transze mają tę samą walutę.
    var averagePurchasePriceInCommonCurrency: Double? {
        guard commonPurchaseCurrency != nil else { return nil }
        let qty = quantity
        guard qty != 0 else { return nil }
        return lots.reduce(0) { $0 + $1.quantity * $1.price } / qty
    }

    /// Oprocentowanie obligacji obowiązujące dziś dla transzy kupionej `purchaseDate`.
    func bondRate(forPurchaseDate purchaseDate: Date) -> Double? {
        guard type == .bond else { return nil }
        return EDOSeries.currentRate(
            purchaseDate: purchaseDate,
            firstYearRate: bondFirstYearRate,
            margin: bondMargin,
            inflation: bondInflation
        )
    }

    /// Oprocentowanie obowiązujące dziś (w procentach) albo nil, jeśli brakuje danych.
    /// Liczone od daty pierwszej transzy (transze jednej serii kupuje się w tym samym miesiącu).
    var currentBondRate: Double? {
        guard let date = firstPurchaseDate else { return nil }
        return bondRate(forPurchaseDate: date)
    }

    /// Czy obligacja ma serię, ale brakuje jej oprocentowania lub marży (do pobrania automatycznie).
    var needsBondRateFetch: Bool {
        guard type == .bond, let series = bondSeries, EDOSeries.normalize(series) != nil else { return false }
        return bondFirstYearRate == nil || bondMargin == nil
    }

    // MARK: - Wycena

    /// Aktualna cena jednostkowa (w USD) używana do wyceny pozycji.
    /// Kolejność: cena pobrana automatycznie -> cena ręczna -> średnia cena zakupu (fallback).
    var currentPrice: Double {
        // Gotówka: fetchedPrice = kurs waluty do USD. Złoto/srebro: fetchedPrice = cena uncji w USD.
        if type == .cash {
            return fetchedPrice ?? manualCurrentPrice ?? 1.0
        }
        if type.autoFetchesPrice || type == .gold || type == .silver, let fetched = fetchedPrice {
            return fetched
        }
        if let manual = manualCurrentPrice {
            let rate: Double
            if let code = manualPriceCurrency, code.uppercased() != "USD" {
                rate = manualPriceCurrencyRate ?? 1.0
            } else {
                rate = 1.0
            }
            return manual * rate
        }
        // Brak ceny rynkowej - wyceniamy po średniej cenie zakupu w USD (np. obligacje bez ceny ręcznej).
        return averagePurchasePriceUSD
    }

    /// Aktualna wartość rynkowa pozycji (w USD).
    var currentValue: Double {
        quantity * currentPrice
    }

    /// Kwota zainwestowana (koszt nabycia) w USD. Dla gotówki równa bieżącej wartości.
    var costBasis: Double {
        if type == .cash { return currentValue }
        return lots.reduce(0) { $0 + $1.costBasisUSD }
    }

    /// Zysk lub strata w USD.
    var profitLoss: Double {
        currentValue - costBasis
    }

    /// Zysk lub strata w procentach względem kosztu nabycia.
    var profitLossPercent: Double {
        guard costBasis != 0 else { return 0 }
        return (profitLoss / costBasis) * 100
    }

    /// Wartość bieżąca pojedynczej transzy (USD).
    func currentValue(of lot: PurchaseLot) -> Double {
        lot.quantity * currentPrice
    }

    /// Zysk/strata pojedynczej transzy (USD). Dla gotówki 0.
    func profitLoss(of lot: PurchaseLot) -> Double {
        if type == .cash { return 0 }
        return currentValue(of: lot) - lot.costBasisUSD
    }

    /// Zysk/strata pojedynczej transzy w procentach.
    func profitLossPercent(of lot: PurchaseLot) -> Double {
        let cost = lot.costBasisUSD
        guard type != .cash, cost != 0 else { return 0 }
        return profitLoss(of: lot) / cost * 100
    }

    // MARK: - Kodowanie (z migracją starego formatu)

    private enum CodingKeys: String, CodingKey {
        case id, name, ticker, type, lots, currency
        case manualCurrentPrice, manualPriceCurrency, manualPriceCurrencyRate
        case fetchedPrice, lastPriceUpdate
        case bondSeries, bondFirstYearRate, bondMargin, bondInflation, bondRateFetchDate
    }

    /// Klucze starego, „płaskiego” formatu (jedno aktywo = jeden zakup).
    private enum LegacyKeys: String, CodingKey {
        case quantity, purchasePrice, purchaseDate, purchaseCurrency, purchaseCurrencyRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        ticker = try c.decodeIfPresent(String.self, forKey: .ticker)
        type = try c.decode(AssetType.self, forKey: .type)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        manualCurrentPrice = try c.decodeIfPresent(Double.self, forKey: .manualCurrentPrice)
        fetchedPrice = try c.decodeIfPresent(Double.self, forKey: .fetchedPrice)
        lastPriceUpdate = try c.decodeIfPresent(Date.self, forKey: .lastPriceUpdate)
        bondSeries = try c.decodeIfPresent(String.self, forKey: .bondSeries)
        bondFirstYearRate = try c.decodeIfPresent(Double.self, forKey: .bondFirstYearRate)
        bondMargin = try c.decodeIfPresent(Double.self, forKey: .bondMargin)
        bondInflation = try c.decodeIfPresent(Double.self, forKey: .bondInflation)
        bondRateFetchDate = try c.decodeIfPresent(Date.self, forKey: .bondRateFetchDate)

        if let lots = try c.decodeIfPresent([PurchaseLot].self, forKey: .lots) {
            self.lots = lots
            manualPriceCurrency = try c.decodeIfPresent(String.self, forKey: .manualPriceCurrency)
            manualPriceCurrencyRate = try c.decodeIfPresent(Double.self, forKey: .manualPriceCurrencyRate)
        } else {
            // Stary format: pola zakupu leżą bezpośrednio w aktywie -> jedna transza.
            // Id transzy = id dawnego aktywa, więc migracja jest deterministyczna.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let purchaseCurrency = try legacy.decodeIfPresent(String.self, forKey: .purchaseCurrency)
            let purchaseCurrencyRate = try legacy.decodeIfPresent(Double.self, forKey: .purchaseCurrencyRate)
            let lot = PurchaseLot(
                id: id,
                date: try legacy.decode(Date.self, forKey: .purchaseDate),
                quantity: try legacy.decode(Double.self, forKey: .quantity),
                price: try legacy.decodeIfPresent(Double.self, forKey: .purchasePrice) ?? 1.0,
                purchaseCurrency: type == .cash ? nil : purchaseCurrency,
                purchaseCurrencyRate: type == .cash ? nil : purchaseCurrencyRate
            )
            lots = [lot]
            // W starym formacie cena ręczna była w walucie zakupu.
            if type != .cash {
                manualPriceCurrency = purchaseCurrency
                manualPriceCurrencyRate = purchaseCurrencyRate
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(ticker, forKey: .ticker)
        try c.encode(type, forKey: .type)
        try c.encode(lots, forKey: .lots)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(manualCurrentPrice, forKey: .manualCurrentPrice)
        try c.encodeIfPresent(manualPriceCurrency, forKey: .manualPriceCurrency)
        try c.encodeIfPresent(manualPriceCurrencyRate, forKey: .manualPriceCurrencyRate)
        try c.encodeIfPresent(fetchedPrice, forKey: .fetchedPrice)
        try c.encodeIfPresent(lastPriceUpdate, forKey: .lastPriceUpdate)
        try c.encodeIfPresent(bondSeries, forKey: .bondSeries)
        try c.encodeIfPresent(bondFirstYearRate, forKey: .bondFirstYearRate)
        try c.encodeIfPresent(bondMargin, forKey: .bondMargin)
        try c.encodeIfPresent(bondInflation, forKey: .bondInflation)
        try c.encodeIfPresent(bondRateFetchDate, forKey: .bondRateFetchDate)
    }
}

// MARK: - Tożsamość pozycji i scalanie transz

extension Asset {

    /// Klucz identyfikujący instrument. Pozycje o tym samym kluczu są scalane w jedną.
    /// - akcje / ETF-y / krypto: typ + ticker (wielkie litery, bez spacji; dla krypto "BTC" == "BTC-USD"),
    /// - gotówka: typ + waluta,
    /// - złoto / srebro: sam typ (jedna cena za uncję),
    /// - obligacje: typ + seria (różne serie mają różne oprocentowanie),
    /// - brak tickera / serii: typ + nazwa.
    var identityKey: String {
        let typeKey = type.rawValue
        let nameKey = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch type {
        case .stock, .etf, .crypto:
            if let normalized = Self.normalizedTicker(ticker, type: type) {
                return "\(typeKey)|ticker:\(normalized)"
            }
            return "\(typeKey)|name:\(nameKey)"
        case .cash:
            return "\(typeKey)|currency:\((currency ?? "USD").uppercased())"
        case .gold, .silver:
            return typeKey
        case .bond:
            let series = (bondSeries ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !series.isEmpty {
                return "\(typeKey)|series:\(EDOSeries.normalize(series) ?? series.uppercased())"
            }
            return "\(typeKey)|name:\(nameKey)"
        }
    }

    /// Ticker w postaci porównywalnej (np. " btc-usd " -> "BTC"), albo nil gdy pusty.
    static func normalizedTicker(_ ticker: String?, type: AssetType) -> String? {
        guard let ticker else { return nil }
        var value = ticker.uppercased().filter { !$0.isWhitespace }
        if type == .crypto, value.hasSuffix("-USD") {
            value = String(value.dropLast(4))
        }
        return value.isEmpty ? nil : value
    }

    /// Dołącza transze `other` do tej pozycji. Pola instrumentu uzupełnia tylko tam,
    /// gdzie tej pozycji ich brakuje (nic nie jest nadpisywane ani gubione).
    mutating func absorb(_ other: Asset) {
        let ownName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherName = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
        for var lot in other.lots {
            // Zachowujemy pierwotną nazwę scalanej pozycji, jeśli była inna.
            if otherName.caseInsensitiveCompare(ownName) != .orderedSame,
               !otherName.isEmpty,
               (lot.note ?? "").isEmpty {
                lot.note = otherName
            }
            // Transza o tym samym id już istnieje - nie dublujemy.
            if !lots.contains(where: { $0.id == lot.id }) {
                lots.append(lot)
            }
        }
        lots.sort { $0.date < $1.date }

        if ticker == nil || ticker?.isEmpty == true { ticker = other.ticker }
        if manualCurrentPrice == nil, let manual = other.manualCurrentPrice {
            manualCurrentPrice = manual
            manualPriceCurrency = other.manualPriceCurrency
            manualPriceCurrencyRate = other.manualPriceCurrencyRate
        }
        // Najświeższa cena pobrana automatycznie.
        if let otherFetched = other.fetchedPrice,
           fetchedPrice == nil || (other.lastPriceUpdate ?? .distantPast) > (lastPriceUpdate ?? .distantPast) {
            fetchedPrice = otherFetched
            lastPriceUpdate = other.lastPriceUpdate
        }
        if bondSeries == nil { bondSeries = other.bondSeries }
        if bondFirstYearRate == nil { bondFirstYearRate = other.bondFirstYearRate }
        if bondMargin == nil { bondMargin = other.bondMargin }
        if bondInflation == nil { bondInflation = other.bondInflation }
        if bondRateFetchDate == nil { bondRateFetchDate = other.bondRateFetchDate }
    }

    /// Scala pozycje o tym samym `identityKey` (kolejność pierwszego wystąpienia zostaje zachowana).
    static func mergedByIdentity(_ assets: [Asset]) -> [Asset] {
        var result: [Asset] = []
        var indexByKey: [String: Int] = [:]
        for asset in assets {
            let key = asset.identityKey
            if let index = indexByKey[key] {
                result[index].absorb(asset)
            } else {
                indexByKey[key] = result.count
                var copy = asset
                copy.lots.sort { $0.date < $1.date }
                result.append(copy)
            }
        }
        return result
    }
}
