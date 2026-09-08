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
    }
    struct Meta: Decodable {
        let regularMarketPrice: Double?
        let currency: String?
        let symbol: String?
    }
    let chart: Chart
}

struct PriceService {

    /// Pobiera aktualną cenę dla podanego tickera.
    /// Dla kryptowalut, jeśli użytkownik nie podał pary walutowej (np. "BTC"),
    /// automatycznie dopisujemy "-USD".
    static func fetchPrice(ticker: String, type: AssetType) async throws -> Double {
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

        guard let price = decoded.chart.result?.first?.meta.regularMarketPrice else {
            throw PriceServiceError.noData
        }

        return price
    }

    /// Pobiera aktualny kurs waluty względem USD (np. PLN → 0.25 oznacza 1 PLN = 0.25 USD).
    /// Używa tickerów Yahoo Finance w formacie PLNUSD=X.
    static func fetchExchangeRate(from currencyCode: String) async throws -> Double {
        let ticker = "\(currencyCode.uppercased())USD=X"
        return try await fetchPrice(ticker: ticker, type: .stock)
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
