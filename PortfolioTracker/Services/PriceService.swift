//
//  PriceService.swift
//  PortfolioTracker
//
//  Odpowiada za pobieranie aktualnych cen z darmowego,
//  nieoficjalnego endpointu Yahoo Finance.
//
//  UWAGA: to jest publiczne, ale nieudokumentowane API Yahoo.
//  Może się czasem zmienić lub zwrócić błąd - dlatego każde pobranie
//  ceny jest opakowane w obsługę błędów, a błąd jednej pozycji
//  nie przerywa odświeżania pozostałych.
//

import Foundation

enum PriceServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Nieprawidłowy adres URL."
        case .invalidResponse: return "Serwer zwrócił nieoczekiwaną odpowiedź."
        case .noData: return "Brak danych o cenie dla tego tickera."
        }
    }
}

/// Struktury pomocnicze do zdekodowania odpowiedzi JSON z Yahoo Finance.
/// Endpoint: https://query1.finance.yahoo.com/v8/finance/chart/{TICKER}
private struct YahooChartResponse: Decodable {
    struct Chart: Decodable {
        let result: [ChartResult]?
    }
    struct ChartResult: Decodable {
        let meta: Meta
        let timestamp: [Double]?
        let indicators: Indicators?
    }
    struct Indicators: Decodable {
        let quote: [QuoteSeries]?
    }
    struct QuoteSeries: Decodable {
        let close: [Double?]?
    }
    struct Meta: Decodable {
        let regularMarketPrice: Double?
        let currency: String?
        let symbol: String?
    }
    let chart: Chart
}

/// Notowanie pobrane z Yahoo Finance: cena w walucie notowania (`meta.currency`).
struct Quote: Equatable {
    let price: Double
    /// Kod waluty dokładnie tak, jak zwraca go Yahoo (np. "USD", "PLN", "GBp"); nil, gdy brak.
    let currency: String?
}

// MARK: - Waluta notowania (czyste funkcje)

/// Przeliczanie cen z waluty notowania Yahoo na USD (wewnętrzną walutę bazową aplikacji).
///
/// Yahoo podaje cenę w walucie giełdy: CDR.WA w PLN, SAP.DE w EUR, a spółki z LSE często
/// w pensach ("GBp"/"GBX") - te trzeba podzielić przez 100, żeby dostać funty (GBP).
enum QuoteCurrency {

    /// Waluty podawane w setnych częściach waluty głównej: kod Yahoo -> (waluta główna, dzielnik).
    /// Uwaga: "GBp" (pensy) różni się od "GBP" (funty) tylko wielkością litery.
    nonisolated private static let minorUnits: [String: (major: String, divisor: Double)] = [
        "GBp": ("GBP", 100), "GBX": ("GBP", 100),
        "ZAc": ("ZAR", 100), "ZAC": ("ZAR", 100),
        "ILA": ("ILS", 100),
    ]

    /// Zamienia cenę w walucie notowania na cenę w walucie głównej (ISO 4217, wielkie litery).
    /// Brak waluty (lub pusty kod) traktujemy jak USD - tak jak aplikacja działała dotąd.
    nonisolated static func normalize(price: Double, currency: String?) -> (price: Double, currency: String) {
        let code = currency?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !code.isEmpty else { return (price, "USD") }
        if let minor = minorUnits[code] {
            return (price / minor.divisor, minor.major)
        }
        return (price, code.uppercased())
    }

    /// Waluta główna, której kursu do USD potrzeba, żeby przeliczyć notowanie (nil dla USD).
    nonisolated static func requiredRateCurrency(for currency: String?) -> String? {
        let code = normalize(price: 0, currency: currency).currency
        return code == "USD" ? nil : code
    }

    /// Przelicza notowanie na USD. `usdRates` to kursy "1 jednostka waluty = x USD"
    /// (te same, które `PriceService.fetchExchangeRate` zwraca dla par XXXUSD=X).
    /// Zwraca nil, gdy brakuje kursu potrzebnej waluty - wtedy nie zgadujemy.
    nonisolated static func priceInUSD(price: Double, currency: String?, usdRates: [String: Double]) -> Double? {
        let normalized = normalize(price: price, currency: currency)
        if normalized.currency == "USD" { return normalized.price }
        guard let rate = usdRates[normalized.currency] else { return nil }
        return normalized.price * rate
    }
}

/// Wybór kursu z dnia zakupu z dziennych notowań Yahoo (czysta funkcja).
enum HistoricalRate {

    /// Zwraca kurs zamknięcia ostatniej sesji, która zaczęła się nie później niż `date`
    /// (zakup w weekend/święto dostaje kurs z ostatniego dnia notowań). Jeśli wszystkie
    /// notowania są późniejsze - bierzemy najwcześniejsze. Puste zamknięcia (null) pomijamy.
    nonisolated static func closeOnOrBefore(_ date: Date, timestamps: [Double], closes: [Double?]) -> Double? {
        let points = zip(timestamps, closes).compactMap { stamp, close -> (Double, Double)? in
            guard let close, close > 0 else { return nil }
            return (stamp, close)
        }.sorted { $0.0 < $1.0 }
        let limit = date.timeIntervalSince1970
        return points.last(where: { $0.0 <= limit })?.1 ?? points.first?.1
    }
}

struct PriceService {

    /// Pobiera aktualną cenę dla podanego tickera (w walucie notowania - patrz `fetchQuote`).
    static func fetchPrice(ticker: String, type: AssetType) async throws -> Double {
        try await fetchQuote(ticker: ticker, type: type).price
    }

    /// Pobiera aktualne notowanie (cena + waluta notowania) dla podanego tickera.
    /// Dla kryptowalut, jeśli użytkownik nie podał pary walutowej (np. "BTC"),
    /// automatycznie dopisujemy "-USD".
    static func fetchQuote(ticker: String, type: AssetType) async throws -> Quote {
        let symbol = normalizedSymbol(ticker: ticker, type: type)

        guard let url = URL(
            string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        ) else {
            throw PriceServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        // Yahoo czasem odrzuca żądania bez nagłówka User-Agent.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PriceServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)

        guard let meta = decoded.chart.result?.first?.meta,
              let price = meta.regularMarketPrice else {
            throw PriceServiceError.noData
        }

        return Quote(price: price, currency: meta.currency)
    }

    /// Pobiera aktualny kurs waluty względem USD (np. PLN → 0.25 oznacza 1 PLN = 0.25 USD).
    /// Używa tickerów Yahoo Finance w formacie PLNUSD=X.
    static func fetchExchangeRate(from currencyCode: String) async throws -> Double {
        let ticker = "\(currencyCode.uppercased())USD=X"
        return try await fetchPrice(ticker: ticker, type: .stock)
    }

    /// Kurs waluty względem USD z dnia `date` (np. z dnia zakupu transzy).
    /// Pobiera dzienne notowania pary XXXUSD=X z okna kilku dni przed tą datą.
    static func fetchHistoricalExchangeRate(from currencyCode: String, on date: Date) async throws -> Double {
        let ticker = "\(currencyCode.uppercased())USD=X"
        let start = Int(date.addingTimeInterval(-10 * 86_400).timeIntervalSince1970)
        let end = Int(date.addingTimeInterval(86_400).timeIntervalSince1970)
        guard let url = URL(
            string: "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&period1=\(start)&period2=\(end)"
        ) else {
            throw PriceServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PriceServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close,
              let rate = HistoricalRate.closeOnOrBefore(date, timestamps: timestamps, closes: closes) else {
            throw PriceServiceError.noData
        }
        return rate
    }

    /// Miesięczne zamknięcia dla tickera z całej dostępnej historii (np. GC=F od 09.2000).
    static func fetchMonthlyHistory(ticker: String) async throws -> [GoldPricePoint] {
        let symbol = ticker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticker
        guard let url = URL(
            string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1mo&range=max"
        ) else {
            throw PriceServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PriceServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close else {
            throw PriceServiceError.noData
        }
        return zip(timestamps, closes).compactMap { stamp, close in
            guard let close, close > 0 else { return nil }
            return GoldPricePoint(date: Date(timeIntervalSince1970: stamp), price: close)
        }
    }

    /// Zamienia ticker wpisany przez użytkownika na symbol zgodny z Yahoo Finance.
    private static func normalizedSymbol(ticker: String, type: AssetType) -> String {
        var symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if type == .crypto && !symbol.contains("-") {
            symbol += "-USD"
        }

        // Proste kodowanie na potrzeby URL (np. dla tickerów z kropką, jak "CDR.WA").
        return symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
    }
}
