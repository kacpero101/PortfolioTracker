//
//  AssetType.swift
//  PortfolioTracker
//
//  Definiuje klasy aktywów, które użytkownik może dodać do portfela.
//

import Foundation

/// Klasa aktywa - decyduje m.in. o tym, czy cena ma być pobierana
/// automatycznie (akcje, ETF-y, krypto) czy wpisywana ręcznie (gotówka, złoto).
enum AssetType: String, Codable, CaseIterable, Identifiable {
    case stock = "Akcje"
    case etf = "ETF"
    /// Obligacje (np. skarbowe EDO). Surowa wartość "Obligacje" musi zostać bez zmian -
    /// jest zapisywana w assets.json.
    case bond = "Obligacje"
    case cash = "Gotówka"
    case crypto = "Kryptowaluty"
    case gold = "Złoto"
    case silver = "Srebro"

    var id: String { rawValue }

    /// Dekodowanie odporne na starsze zapisy: oprócz bieżących wartości akceptujemy
    /// liczbę pojedynczą, małe litery, brak polskich znaków i nazwy angielskie
    /// (np. "Kryptowaluta", "Obligacja", "akcje", "Gotowka"). Zapis zawsze używa `rawValue`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let type = AssetType(lenientRawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Nieznana klasa aktywa: \(raw)"
            )
        }
        self = type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Bieżąca wartość albo jeden z aliasów (bez rozróżniania wielkości liter i polskich znaków).
    init?(lenientRawValue raw: String) {
        if let exact = AssetType(rawValue: raw) {
            self = exact
            return
        }
        let key = Self.foldedKey(raw)
        guard let match = Self.aliases[key] else { return nil }
        self = match
    }

    /// Aliasy po normalizacji `foldedKey` (małe litery, bez polskich znaków i separatorów).
    private static let aliases: [String: AssetType] = {
        var map: [String: AssetType] = [:]
        let table: [AssetType: [String]] = [
            .stock: ["akcje", "akcja", "akcji", "stock", "stocks", "share", "shares"],
            .etf: ["etf", "etfy", "etfs"],
            .bond: ["obligacje", "obligacja", "obligacji", "bond", "bonds"],
            .cash: ["gotowka", "cash"],
            .crypto: ["kryptowaluty", "kryptowaluta", "krypto", "crypto", "cryptocurrency", "cryptocurrencies"],
            .gold: ["zloto", "gold"],
            .silver: ["srebro", "silver"]
        ]
        for (type, names) in table {
            for name in names { map[foldedKey(name)] = type }
            map[foldedKey(type.rawValue)] = type
        }
        return map
    }()

    private static func foldedKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Czy dla tego typu aktywa próbujemy pobrać cenę z Yahoo Finance.
    /// Obligacje i gotówka nie mają jednego, uniwersalnego tickera giełdowego,
    /// więc ich wycena jest ustalana ręcznie przez użytkownika.
    var autoFetchesPrice: Bool {
        switch self {
        case .stock, .etf, .crypto:
            return true
        case .bond, .cash, .gold, .silver:
            return false
        }
    }

    /// Krótka podpowiedź, jak wpisać ticker dla danego typu.
    var tickerHint: String {
        switch self {
        case .stock: return "np. AAPL, CDR.WA (dla GPW dodaj .WA)"
        case .etf: return "np. VOO, SPY, IWDA.L"
        case .crypto: return "np. BTC, ETH (dopiszemy -USD automatycznie)"
        case .bond, .cash, .gold, .silver: return "ticker niewymagany"
        }
    }
}
