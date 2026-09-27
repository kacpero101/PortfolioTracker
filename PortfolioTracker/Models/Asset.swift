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

    // MARK: - Obligacje skarbowe EDO
    //
    // Wszystkie pola są opcjonalne, więc starsze pliki assets.json (bez tych kluczy)
    // nadal wczytują się poprawnie - brakujące klucze dekodują się jako nil.

    /// Seria obligacji EDO, np. "EDO0936" (sprzedaż we wrześniu 2026, wykup we wrześniu 2036).
    var bondSeries: String?

    /// Oprocentowanie w pierwszym rocznym okresie odsetkowym, w procentach (np. 5.35).
    var bondFirstYearRate: Double?

    /// Marża ponad inflację obowiązująca od drugiego roku, w procentach (np. 2.00).
    var bondMargin: Double?

    /// Inflacja (CPI r/r) przyjęta dla bieżącego okresu odsetkowego, w procentach - wpisywana ręcznie.
    var bondInflation: Double?

    /// Kiedy oprocentowanie zostało ostatnio pobrane z obligacjeskarbowe.pl (nil = wpisane ręcznie).
    var bondRateFetchDate: Date?

    /// Oprocentowanie obowiązujące dziś (w procentach) albo nil, jeśli brakuje danych.
    /// W pierwszym roku: stawka z listu emisyjnego; później: marża + max(inflacja, 0).
    var currentBondRate: Double? {
        guard type == .bond else { return nil }
        return EDOSeries.currentRate(
            purchaseDate: purchaseDate,
            firstYearRate: bondFirstYearRate,
            margin: bondMargin,
            inflation: bondInflation
        )
    }

    // MARK: - Wartości wyliczane

    /// Aktualna cena jednostkowa (w USD) używana do wyceny pozycji.
    /// Kolejność: cena pobrana automatycznie -> cena ręczna -> cena zakupu (fallback).
    var currentPrice: Double {
        // Gotówka: fetchedPrice = kurs waluty do USD. Złoto: fetchedPrice = cena uncji w USD.
        if type == .cash {
            return fetchedPrice ?? manualCurrentPrice ?? 1.0
        }
        if type.autoFetchesPrice || type == .gold || type == .silver, let fetched = fetchedPrice {
            return fetched
        }
        // Cena ręczna i cena zakupu są podawane w walucie zakupu, więc - tak jak w costBasis -
        // przeliczamy je na USD. Wcześniej np. obligacja kupiona w PLN była wyceniana w PLN,
        // a koszt w USD, co dawało fikcyjny zysk rzędu kilkuset procent.
        let rate = purchaseCurrencyRate ?? 1.0
        return (manualCurrentPrice ?? purchasePrice) * rate
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
