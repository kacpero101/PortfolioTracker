//
//  AssetType.swift
//  PortfolioTracker
//
//  Definiuje klasy aktywów, które użytkownik może dodać do portfela.
//

import SwiftUI

/// Klasa aktywa - decyduje m.in. o tym, czy cena ma być pobierana
/// automatycznie (akcje, ETF-y, krypto) czy wpisywana ręcznie (gotówka, złoto).
enum AssetType: String, Codable, CaseIterable, Identifiable {
    case stock = "Akcje"
    case etf = "ETF"
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
        case .cash, .gold, .silver:
            return false
        }
    }

    /// Kolor używany na wykresie kołowym alokacji.
    var color: Color {
        switch self {
        case .stock: return .blue
        case .etf: return .green
        case .cash: return .gray
        case .crypto: return .purple
        case .gold: return Color(red: 0.85, green: 0.68, blue: 0.10)
        case .silver: return Color(red: 0.72, green: 0.72, blue: 0.72)
        }
    }

    /// Krótka podpowiedź, jak wpisać ticker dla danego typu.
    var tickerHint: String {
        switch self {
        case .stock: return "np. AAPL, CDR.WA (dla GPW dodaj .WA)"
        case .etf: return "np. VOO, SPY, IWDA.L"
        case .crypto: return "np. BTC, ETH (dopiszemy -USD automatycznie)"
        case .cash, .gold, .silver: return "ticker niewymagany"
        }
    }
}
