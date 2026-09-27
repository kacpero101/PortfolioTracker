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
    /// jest zapisywana w assets.json, a jej brak uniemożliwia wczytanie starszych danych.
    case bond = "Obligacje"
    case cash = "Gotówka"
    case crypto = "Kryptowaluty"
    case gold = "Złoto"
    case silver = "Srebro"

    var id: String { rawValue }

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
