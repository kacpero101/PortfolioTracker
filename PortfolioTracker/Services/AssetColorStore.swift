//
//  AssetColorStore.swift
//  PortfolioTracker
//
//  Przechowuje kolory przypisane do klas aktywów.
//  Kolory są wybierane z palety 16 presetów i zapisywane w UserDefaults.
//

import SwiftUI
import Combine

final class AssetColorStore: ObservableObject {

    /// Paleta 16 dostępnych kolorów.
    static let palette: [Color] = [
        .blue,                                          //  0 – domyślny dla Akcji
        .green,                                         //  1 – domyślny dla ETF
        .orange,                                        //  2 – domyślny dla Obligacji
        .gray,                                          //  3 – domyślny dla Gotówki
        .purple,                                        //  4 – domyślny dla Krypto
        .red,                                           //  5
        Color(red: 0.85, green: 0.10, blue: 0.60),     //  6 – fuksja
        .yellow,                                        //  7
        .teal,                                          //  8 – domyślny dla Srebra
        .indigo,                                        //  9
        Color(red: 0.45, green: 0.45, blue: 0.05),     // 10 – oliwkowy
        .brown,                                         // 11
        Color(red: 0.85, green: 0.68, blue: 0.10),     // 12 – złoty
        Color(red: 0.55, green: 0.05, blue: 0.08),     // 13 – bordowy
        Color(red: 0.05, green: 0.55, blue: 0.35),     // 14 – szmaragdowy
        Color(red: 0.65, green: 0.55, blue: 0.90),     // 15 – lawendowy
    ]

    /// Domyślne kolory - używane tylko dla klas, których kolor użytkownik nie zmienił
    /// (wybory użytkownika są zapisane w UserDefaults i mają pierwszeństwo).
    /// Każda klasa ma inny kolor, żeby dało się je odróżnić na wykresie.
    static let defaultIndices: [AssetType: Int] = [
        .stock: 0, .etf: 1, .bond: 2, .cash: 3, .crypto: 4, .gold: 12, .silver: 8,
    ]

    @Published private var colorIndices: [String: Int] = [:]

    private let storageKey = "assetTypeColorIndices"

    init() { load() }

    func color(for type: AssetType) -> Color {
        Self.palette[colorIndex(for: type)]
    }

    func colorIndex(for type: AssetType) -> Int {
        colorIndices[type.rawValue] ?? Self.defaultIndices[type] ?? 0
    }

    func setColor(index: Int, for type: AssetType) {
        colorIndices[type.rawValue] = index
        save()
    }

    private func save() {
        UserDefaults.standard.set(colorIndices, forKey: storageKey)
    }

    private func load() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int] {
            colorIndices = saved
        }
    }
}
