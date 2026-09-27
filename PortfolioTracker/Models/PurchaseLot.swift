//
//  PurchaseLot.swift
//  PortfolioTracker
//
//  Pojedyncza transza zakupu w ramach pozycji (np. drugi zakup BTC).
//  Pozycja (`Asset`) opisuje instrument, a jej transze - kolejne zakupy.
//

import Foundation

struct PurchaseLot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var date: Date

    /// Ilość jednostek kupionych w tej transzy (dla gotówki: kwota w walucie pozycji).
    var quantity: Double

    /// Cena zakupu za jednostkę w walucie `purchaseCurrency` (dla gotówki zawsze 1).
    var price: Double

    /// Waluta zakupu (nil = USD).
    var purchaseCurrency: String?

    /// Kurs purchaseCurrency→USD z dnia zakupu (1 jednostka waluty = x USD).
    var purchaseCurrencyRate: Double?

    /// Opcjonalna notatka (np. „zakup na Binance”). Przy scalaniu starszych danych trafia tu
    /// pierwotna nazwa pozycji, jeśli różniła się od nazwy scalonej pozycji.
    var note: String?

    /// true, gdy `purchaseCurrencyRate` to kurs z dnia zakupu (pobrany z historii notowań).
    /// Taki kurs jest stały - odświeżanie cen go nie nadpisuje. nil/false oznacza kurs
    /// tymczasowy (np. bieżący albo ze starszej wersji aplikacji), który trzeba jeszcze ustalić.
    var purchaseRateIsHistorical: Bool? = nil

    /// Czy transza czeka na pobranie kursu z dnia zakupu.
    var needsHistoricalRate: Bool {
        guard let code = purchaseCurrency, code.uppercased() != "USD" else { return false }
        return purchaseRateIsHistorical != true
    }

    /// Kurs do USD używany w wyliczeniach (brak waluty albo brak kursu = 1).
    var usdRate: Double {
        guard let code = purchaseCurrency, code.uppercased() != "USD" else { return 1.0 }
        return purchaseCurrencyRate ?? 1.0
    }

    /// Koszt transzy w USD.
    var costBasisUSD: Double {
        quantity * price * usdRate
    }

    /// Kod waluty zakupu do wyświetlenia (nil -> "USD").
    var displayCurrency: String {
        purchaseCurrency?.uppercased() ?? "USD"
    }
}
