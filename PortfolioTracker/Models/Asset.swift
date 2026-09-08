//
//  Asset.swift
//  PortfolioTracker
//
//  Reprezentuje pojedynczą pozycję w portfelu (np. 10 akcji Apple).
//

import Foundation

struct Asset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    /// Własna nazwa aktywa, np. "Apple Inc." albo "Obligacje skarbowe EDO0433"
    var name: String

    /// Ticker giełdowy używany do pobierania ceny (akcje / ETF-y / krypto).
    /// Dla obligacji i gotówki może być pusty.
    var ticker: String?

    var type: AssetType

    /// Ilość jednostek (liczba akcji, sztuk ETF, jednostek krypto, wartość nominalna obligacji, kwota gotówki).
    var quantity: Double

    /// Cena zakupu za jedną jednostkę (w walucie notowania).
    var purchasePrice: Double

    var purchaseDate: Date

    /// Waluta gotówki - wypełniana tylko gdy type == .cash.
    var currency: String?

    /// Waluta, w której dokonano zakupu (nil = USD). Dotyczy wszystkich klas poza gotówką.
    var purchaseCurrency: String?

    /// Kurs purchaseCurrency→USD pobierany automatycznie przy odświeżeniu cen.
    var purchaseCurrencyRate: Double?

    /// Cena ustawiana ręcznie - używana gdy pobranie ceny się nie powiedzie.
    var manualCurrentPrice: Double?

    /// Ostatnia cena pobrana automatycznie z Yahoo Finance.
    var fetchedPrice: Double?

    var lastPriceUpdate: Date?

    // MARK: - Wartości wyliczane

    /// Aktualna cena jednostkowa używana do wyceny pozycji.
    /// Kolejność: cena pobrana automatycznie -> cena ręczna -> cena zakupu (fallback).
    var currentPrice: Double {
        // Gotówka: fetchedPrice = kurs waluty do USD. Złoto: fetchedPrice = cena uncji w USD.
        if type == .cash {
            return fetchedPrice ?? manualCurrentPrice ?? 1.0
        }
        if type == .gold || type == .silver {
            return fetchedPrice ?? manualCurrentPrice ?? purchasePrice
        }
        if type.autoFetchesPrice, let fetched = fetchedPrice {
            return fetched
        }
        if let manual = manualCurrentPrice {
            return manual
        }
        return purchasePrice
    }

    /// Aktualna wartość rynkowa pozycji.
    var currentValue: Double {
        quantity * currentPrice
    }

    /// Kwota zainwestowana (koszt nabycia) w USD.
    /// Dla gotówki zwraca currentValue. Dla pozostałych: quantity × purchasePrice × kurs_do_USD.
    var costBasis: Double {
        if type == .cash { return currentValue }
        return quantity * purchasePrice * (purchaseCurrencyRate ?? 1.0)
    }

    /// Zysk lub strata w walucie.
    var profitLoss: Double {
        currentValue - costBasis
    }

    /// Zysk lub strata w procentach względem kosztu nabycia.
    var profitLossPercent: Double {
        guard costBasis != 0 else { return 0 }
        return (profitLoss / costBasis) * 100
    }
}
