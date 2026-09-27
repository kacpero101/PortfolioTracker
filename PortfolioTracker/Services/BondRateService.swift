//
//  BondRateService.swift
//  PortfolioTracker
//
//  Pobiera oprocentowanie serii obligacji skarbowych EDO (10-letnich, indeksowanych inflacją)
//  ze strony obligacjeskarbowe.pl, np.:
//  https://www.obligacjeskarbowe.pl/oferta-obligacji/obligacje-10-letnie-edo/edo0936/
//
//  Strona nie ma publicznego API, więc parsujemy HTML. Parsowanie jest czystą funkcją
//  (`parseSeriesPage`), którą można testować bez sieci. Oprocentowanie danej serii nie zmienia
//  się po ogłoszeniu, więc raz pobrane wyniki trzymamy w pamięci podręcznej (UserDefaults).
//  Gdy pobranie się nie uda, użytkownik zawsze może wpisać oprocentowanie ręcznie.
//

import Foundation

// MARK: - Seria EDO (czyste funkcje pomocnicze)

enum EDOSeries {

    /// Kod serii dla obligacji kupionej w danym miesiącu.
    /// Symbol zawiera miesiąc i rok WYKUPU (zakup + 10 lat), np. wrzesień 2026 -> "EDO0936".
    nonisolated static func code(forPurchaseDate date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let maturityYear = ((components.year ?? 2000) + 10) % 100
        return String(format: "EDO%02d%02d", month, maturityYear)
    }

    /// Normalizuje wpisany kod (np. " edo 0936 ") do postaci "EDO0936".
    /// Zwraca nil, jeśli kod nie ma formatu EDO + miesiąc (01-12) + dwie cyfry roku.
    nonisolated static func normalize(_ input: String) -> String? {
        let code = input.uppercased().filter { !$0.isWhitespace }
        guard code.count == 7, code.hasPrefix("EDO") else { return nil }
        let digits = code.dropFirst(3)
        guard digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let month = Int(digits.prefix(2)), (1...12).contains(month) else {
            return nil
        }
        return code
    }

    /// Oprocentowanie obowiązujące w dniu `now` (w procentach).
    /// - W pierwszym roku od zakupu: stawka z pierwszego okresu odsetkowego.
    /// - W kolejnych latach: marża + inflacja (ujemna inflacja liczona jako 0).
    /// Zwraca nil, jeśli brakuje danych potrzebnych do wyliczenia.
    nonisolated static func currentRate(
        purchaseDate: Date,
        firstYearRate: Double?,
        margin: Double?,
        inflation: Double?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let firstPeriodEnd = calendar.date(byAdding: .year, value: 1, to: purchaseDate) ?? purchaseDate
        if now < firstPeriodEnd {
            return firstYearRate
        }
        guard let margin, let inflation else { return nil }
        return margin + max(inflation, 0)
    }
}

// MARK: - Wynik i błędy

/// Oprocentowanie jednej serii EDO pobrane z obligacjeskarbowe.pl.
struct EDOSeriesRate: Codable, Equatable {
    let series: String
    /// Oprocentowanie w pierwszym rocznym okresie odsetkowym (w procentach).
    let firstYearRate: Double
    /// Marża ponad inflację od drugiego roku (w procentach). Starsze strony serii jej nie podają.
    let margin: Double?
    let fetchedAt: Date
}

enum BondRateError: LocalizedError {
    case invalidSeries(String)
    case seriesNotFound(String)
    case offline
    case invalidResponse
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidSeries(let code):
            return "Nieprawidłowy kod serii „\(code)”. Oczekiwany format: EDOMMRR, np. EDO0936."
        case .seriesNotFound(let code):
            return "Nie znaleziono serii \(code) na obligacjeskarbowe.pl."
        case .offline:
            return "Brak połączenia z internetem. Wpisz oprocentowanie ręcznie."
        case .invalidResponse:
            return "Serwer obligacjeskarbowe.pl zwrócił nieoczekiwaną odpowiedź."
        case .parseFailed:
            return "Nie udało się odczytać oprocentowania ze strony. Wpisz je ręcznie."
        }
    }
}

// MARK: - Serwis

@MainActor
final class BondRateService {

    static let shared = BondRateService()

    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheKey = "edoSeriesRateCache"
    private var cache: [String: EDOSeriesRate] = [:]

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        loadCache()
    }

    /// Ostatnio zapisane oprocentowanie serii (bez sieci).
    func cachedRate(for series: String) -> EDOSeriesRate? {
        guard let code = EDOSeries.normalize(series) else { return nil }
        return cache[code]
    }

    /// Zwraca oprocentowanie serii - z pamięci podręcznej albo pobrane z obligacjeskarbowe.pl.
    /// Oprocentowanie ogłoszonej serii się nie zmienia, więc cache nie ma daty ważności;
    /// `forceRefresh` pozwala mimo to pobrać dane ponownie.
    func rate(for series: String, forceRefresh: Bool = false) async throws -> EDOSeriesRate {
        guard let code = EDOSeries.normalize(series) else {
            throw BondRateError.invalidSeries(series)
        }
        if !forceRefresh, let cached = cache[code] {
            return cached
        }

        var request = URLRequest(url: Self.url(for: code))
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.isOfflineError(error) {
            throw BondRateError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw BondRateError.invalidResponse
        }
        if http.statusCode == 404 {
            throw BondRateError.seriesNotFound(code)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BondRateError.invalidResponse
        }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let parsed = try Self.parseSeriesPage(html, series: code)
        let result = EDOSeriesRate(
            series: code,
            firstYearRate: parsed.firstYearRate,
            margin: parsed.margin,
            fetchedAt: Date()
        )
        cache[code] = result
        saveCache()
        return result
    }

    // MARK: - Czyste funkcje (testowalne bez sieci)

    /// Adres strony serii, np. .../obligacje-10-letnie-edo/edo0936/
    nonisolated static func url(for series: String) -> URL {
        URL(string: "https://www.obligacjeskarbowe.pl/oferta-obligacji/obligacje-10-letnie-edo/\(series.lowercased())/")!
    }

    /// Wyciąga oprocentowanie pierwszego roku i marżę ze strony serii EDO.
    ///
    /// Obsługiwane warianty strony (stan na wrzesień 2026):
    /// - nowsze serie: pole „Oprocentowanie:” zawiera np.
    ///   „5,35% w pierwszym rocznym okresie odsetkowym, (...) marża 2,00% + inflacja”,
    /// - starsze serie: pole bez liczby; stawka jest w zdaniu
    ///   „W pierwszym rocznym okresie odsetkowym wynosi 2,50%” oraz w nagłówku („2,50<sub>%</sub>”);
    ///   marży wtedy nie ma na stronie (tylko w liście emisyjnym PDF) - zwracamy nil.
    nonisolated static func parseSeriesPage(
        _ html: String,
        series: String
    ) throws -> (firstYearRate: Double, margin: Double?) {
        // 1. Strona musi dotyczyć właściwej serii - tytuł zaczyna się od kodu, np. "EDO0936 | ...".
        guard let title = firstMatch(#"<title>([^<]*)"#, in: html),
              title.uppercased().contains(series.uppercased()) else {
            throw BondRateError.seriesNotFound(series)
        }

        // 2. Pole „Oprocentowanie:” w szczegółach produktu.
        let details = firstMatch(
            #"Oprocentowanie:\s*</strong>\s*<span[^>]*>(.*?)</span>"#,
            in: html
        ).map(plainText) ?? ""

        let number = #"(\d{1,2}(?:[.,]\d{1,2})?)"#
        let firstYearRate =
            firstNumber(number + #"\s*%\s*w\s+pierwszym"#, in: details)
            ?? firstNumber(#"w\s+pierwszym\s+rocznym\s+okresie\s+odsetkowym\s+wynosi\s*"# + number + #"\s*%"#,
                           in: plainText(html))
            ?? firstNumber(#"hero__image.*?"# + number + #"\s*<sub>\s*%"#, in: html)

        guard let firstYearRate, (0...30).contains(firstYearRate) else {
            throw BondRateError.parseFailed
        }

        let margin = firstNumber(#"marża\s*"# + number + #"\s*%"#, in: details)
            .flatMap { (0...10).contains($0) ? $0 : nil }

        return (firstYearRate, margin)
    }

    // MARK: - Prywatne

    nonisolated private static func isOfflineError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Pierwsza grupa przechwytująca pierwszego dopasowania (bez rozróżniania wielkości liter,
    /// `.` dopasowuje też znaki nowej linii).
    nonisolated private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// Jak `firstMatch`, ale od razu zamienia polski zapis liczby („5,35”) na Double.
    nonisolated private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        firstMatch(pattern, in: text).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// Usuwa znaczniki HTML i najczęstsze encje, sklejając białe znaki.
    nonisolated private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in ["&nbsp;": " ", "&#160;": " ", "&oacute;": "ó", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: EDOSeriesRate].self, from: data) else {
            return
        }
        cache = decoded
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}
