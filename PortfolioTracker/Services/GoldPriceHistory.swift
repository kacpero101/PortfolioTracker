//
//  GoldPriceHistory.swift
//  PortfolioTracker
//
//  Historia ceny złota w USD za uncję trojańską (1975 - dziś) do wykresu w tle aplikacji.
//
//  Źródła:
//  - 1975-1999: średnie roczne ceny LBMA (wbudowane - Yahoo nie ma tak starych notowań),
//  - od 09.2000: miesięczne zamknięcia kontraktu GC=F z Yahoo Finance, pobierane i
//    zapisywane w pamięci podręcznej; bez internetu używamy wbudowanych średnich rocznych.
//

import Combine
import Foundation

struct GoldPricePoint: Identifiable, Equatable, Codable {
    let date: Date
    let price: Double
    var id: Date { date }
}

enum GoldPriceHistory {

    /// Średnie roczne ceny złota (USD/oz). Lata 1975-1999 wg LBMA, 2000-2025 wg średnich
    /// z miesięcznych notowań GC=F - tylko awaryjnie, gdy nie da się pobrać danych z Yahoo.
    nonisolated static let annualAverages: [Int: Double] = [
        1975: 161, 1976: 125, 1977: 148, 1978: 193, 1979: 307,
        1980: 612, 1981: 460, 1982: 376, 1983: 424, 1984: 361,
        1985: 317, 1986: 368, 1987: 447, 1988: 437, 1989: 381,
        1990: 384, 1991: 362, 1992: 344, 1993: 360, 1994: 384,
        1995: 384, 1996: 388, 1997: 331, 1998: 294, 1999: 279,
        2000: 272, 2001: 273, 2002: 308, 2003: 370, 2004: 413,
        2005: 452, 2006: 619, 2007: 712, 2008: 872, 2009: 975,
        2010: 1237, 2011: 1578, 2012: 1678, 2013: 1420, 2014: 1245,
        2015: 1152, 2016: 1250, 2017: 1272, 2018: 1263, 2019: 1385,
        2020: 1800, 2021: 1790, 2022: 1794, 2023: 1961, 2024: 2365,
        2025: 3515,
    ]

    /// Punkt w połowie roku (1 lipca) dla średniej rocznej.
    nonisolated static func midYear(_ year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = 7
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    /// Łączy średnie roczne sprzed danych miesięcznych z danymi miesięcznymi (czysta funkcja).
    /// Średnie roczne są używane tylko dla lat, zanim zaczynają się dane miesięczne.
    nonisolated static func combined(monthly: [GoldPricePoint]) -> [GoldPricePoint] {
        let sortedMonthly = monthly.filter { $0.price > 0 }.sorted { $0.date < $1.date }
        let cutoff = sortedMonthly.first?.date ?? .distantFuture
        let annual = annualAverages
            .map { GoldPricePoint(date: midYear($0.key), price: $0.value) }
            .filter { $0.date < cutoff }
            .sorted { $0.date < $1.date }
        return annual + sortedMonthly
    }
}

/// Dostarcza dane do wykresu w tle: najpierw z pamięci podręcznej / wbudowane,
/// potem (raz na dobę) odświeżone z Yahoo Finance.
@MainActor
final class GoldPriceHistoryModel: ObservableObject {
    @Published private(set) var points: [GoldPricePoint]

    private let cacheKey = "goldMonthlyHistory.v1"
    private let cacheDateKey = "goldMonthlyHistory.v1.date"

    init() {
        points = GoldPriceHistory.combined(monthly: [])
        if let cached = Self.loadCache(key: cacheKey) {
            points = GoldPriceHistory.combined(monthly: cached)
        }
    }

    func refreshIfNeeded() async {
        if let last = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Date().timeIntervalSince(last) < 86_400 {
            return
        }
        do {
            let monthly = try await PriceService.fetchMonthlyHistory(ticker: "GC=F")
            guard !monthly.isEmpty else { return }
            points = GoldPriceHistory.combined(monthly: monthly)
            if let data = try? JSONEncoder().encode(monthly) {
                UserDefaults.standard.set(data, forKey: cacheKey)
                UserDefaults.standard.set(Date(), forKey: cacheDateKey)
            }
        } catch {
            // Tło jest tylko ozdobą - bez internetu zostają dane wbudowane lub z pamięci podręcznej.
            print("Nie udało się pobrać historii ceny złota: \(error)")
        }
    }

    private static func loadCache(key: String) -> [GoldPricePoint]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([GoldPricePoint].self, from: data)
    }
}
