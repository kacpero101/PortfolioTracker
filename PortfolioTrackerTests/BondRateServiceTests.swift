//
//  BondRateServiceTests.swift
//  PortfolioTrackerTests
//
//  Testy parsowania stron serii EDO z obligacjeskarbowe.pl oraz zgodności wstecznej modelu.
//  Fragmenty HTML odwzorowują strukturę strony (stan na wrzesień 2026) - bez dostępu do sieci.
//

import Foundation
import Testing
@testable import PortfolioTracker

@MainActor
struct BondRateServiceTests {

    // MARK: - Fragmenty stron

    /// Nowsza seria: stawka i marża w polu „Oprocentowanie:”.
    private let edo0936Page = """
    <html><head><title>EDO0936 | Obligacje 10-letnie EDO | Oferta obligacji | Obligacje skarbowe</title></head>
    <body>
    <figure class="hero__image"><figcaption><span class="colors--green">
        5,35<sub>%</sub>
    </span></figcaption></figure>
    <ul>
      <li>
        <strong class="product-details__list-label">Seria:</strong>
        <span class="product-details__list-value"> EDO0936 </span>
      </li>
      <li>
        <strong class="product-details__list-label">Oprocentowanie:</strong>
        <span class="product-details__list-value">
            5,35% w pierwszym rocznym okresie odsetkowym, w kolejnych rocznych okresach odsetkowych: marża 2,00% + inflacja
        </span>
      </li>
    </ul>
    <p>W pierwszym roku (okresie odsetkowym) oprocentowanie jest naliczane od wartości 100 zł.</p>
    <div>Inne obligacje: 4,75 % 4,15 %</div>
    </body></html>
    """

    /// Starsza seria: pole „Oprocentowanie:” bez liczby, stawka tylko w opisie i nagłówku, brak marży.
    private let edo0126Page = """
    <html><head><title>EDO0126 | Obligacje 10-letnie EDO | Oferta obligacji | Obligacje skarbowe</title></head>
    <body>
    <figure class="hero__image"><figcaption><span class="colors--green">
        2,50<sub>%</sub>
    </span></figcaption></figure>
    <li>
      <strong class="product-details__list-label">Oprocentowanie:</strong>
      <span class="product-details__list-value">
          w pierwszym rocznym okresie odsetkowym, z roczną kapitalizacją odsetek
      </span>
    </li>
    <ul><li>oprocentowanie jest zmienne. W pierwszym rocznym okresie odsetkowym wynosi 2,50%. W kolejnych
    rocznych okresach odsetkowych jest obliczane jako suma inflacji i marży odsetkowej,</li></ul>
    </body></html>
    """

    // MARK: - Parsowanie

    @Test func parsesFirstYearRateAndMarginFromCurrentSeries() throws {
        let result = try BondRateService.parseSeriesPage(edo0936Page, series: "EDO0936")
        #expect(result.firstYearRate == 5.35)
        #expect(result.margin == 2.00)
    }

    @Test func parsesOlderSeriesWithoutMargin() throws {
        let result = try BondRateService.parseSeriesPage(edo0126Page, series: "EDO0126")
        #expect(result.firstYearRate == 2.50)
        #expect(result.margin == nil)
    }

    @Test func rejectsPageOfDifferentSeries() {
        #expect(throws: BondRateError.self) {
            try BondRateService.parseSeriesPage(edo0936Page, series: "EDO0836")
        }
    }

    @Test func failsWhenRateIsMissing() {
        let page = "<html><head><title>EDO0936 | Obligacje</title></head><body>Brak danych</body></html>"
        #expect(throws: BondRateError.self) {
            try BondRateService.parseSeriesPage(page, series: "EDO0936")
        }
    }

    @Test func buildsSeriesURL() {
        #expect(BondRateService.url(for: "EDO0936").absoluteString
                == "https://www.obligacjeskarbowe.pl/oferta-obligacji/obligacje-10-letnie-edo/edo0936/")
    }

    // MARK: - Kod serii

    @Test func seriesCodeUsesMaturityMonthAndYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let september2026 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let january2095 = calendar.date(from: DateComponents(year: 2095, month: 1, day: 2))!
        #expect(EDOSeries.code(forPurchaseDate: september2026, calendar: calendar) == "EDO0936")
        #expect(EDOSeries.code(forPurchaseDate: january2095, calendar: calendar) == "EDO0105")
    }

    @Test func normalizesSeriesCode() {
        #expect(EDOSeries.normalize(" edo 0936 ") == "EDO0936")
        #expect(EDOSeries.normalize("EDO1336") == nil)
        #expect(EDOSeries.normalize("COI0936") == nil)
        #expect(EDOSeries.normalize("EDO093") == nil)
    }

    @Test func currentRateUsesFirstYearRateThenMarginPlusInflation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let purchase = calendar.date(from: DateComponents(year: 2025, month: 3, day: 10))!
        let inFirstYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 1))!
        let inSecondYear = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!

        #expect(EDOSeries.currentRate(purchaseDate: purchase, firstYearRate: 6.8, margin: 2.0,
                                      inflation: 3.1, now: inFirstYear, calendar: calendar) == 6.8)
        let secondYearRate = EDOSeries.currentRate(purchaseDate: purchase, firstYearRate: 6.8, margin: 2.0,
                                                   inflation: 3.1, now: inSecondYear, calendar: calendar)
        #expect(abs((secondYearRate ?? 0) - 5.1) < 0.000001)
        // Ujemna inflacja liczona jako 0.
        #expect(EDOSeries.currentRate(purchaseDate: purchase, firstYearRate: 6.8, margin: 2.0,
                                      inflation: -1.0, now: inSecondYear, calendar: calendar) == 2.0)
        // Brak inflacji po pierwszym roku - nie zgadujemy.
        #expect(EDOSeries.currentRate(purchaseDate: purchase, firstYearRate: 6.8, margin: 2.0,
                                      inflation: nil, now: inSecondYear, calendar: calendar) == nil)
    }

    // MARK: - Zgodność wsteczna danych

    @Test func decodesAssetsSavedBeforeBondFields() throws {
        let json = """
        [{
          "id": "7A1C6A2E-2F0B-4C1B-9B7D-2E2A1B0C9D11",
          "name": "Obligacje skarbowe EDO0433",
          "type": "Obligacje",
          "quantity": 10,
          "purchasePrice": 100,
          "purchaseDate": "2023-04-15T00:00:00Z",
          "purchaseCurrency": "PLN",
          "purchaseCurrencyRate": 0.25
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let assets = try decoder.decode([Asset].self, from: Data(json.utf8))
        #expect(assets.first?.type == .bond)
        #expect(assets.first?.bondSeries == nil)
        #expect(assets.first?.bondFirstYearRate == nil)
    }

    @Test func manualBondPriceIsConvertedToUSDLikeCostBasis() {
        var asset = Asset(name: "EDO", ticker: nil, type: .bond, quantity: 10,
                          purchasePrice: 100, purchaseDate: Date())
        asset.purchaseCurrency = "PLN"
        asset.purchaseCurrencyRate = 0.25
        // Bez ceny ręcznej wartość = koszt, więc zysk wynosi 0 (a nie +300%).
        #expect(asset.currentValue == asset.costBasis)
        asset.manualCurrentPrice = 110
        #expect(asset.currentValue == 275)
    }
}
