//
//  AddAssetView.swift
//  PortfolioTracker
//
//  Formularz dodawania nowego aktywa lub edycji istniejącego.
//  Jeśli `assetToEdit` jest podany, formularz działa w trybie edycji.
//

import SwiftUI

struct AddAssetView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    let assetToEdit: Asset?

    // Pola formularza - trzymane osobno, żeby łatwo je walidować i wiązać z UI.
    @State private var name: String = ""
    @State private var ticker: String = ""
    @State private var type: AssetType = .stock
    @State private var quantityText: String = ""
    @State private var purchasePriceText: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var manualPriceText: String = ""
    @State private var currency: String = "PLN"
    @State private var purchaseCurrency: String = "USD"

    // Obligacje skarbowe EDO
    @State private var isEDO: Bool = true
    @State private var bondSeriesText: String = ""
    @State private var firstYearRateText: String = ""
    @State private var marginText: String = ""
    @State private var inflationText: String = ""
    @State private var bondRateFetchDate: Date?
    @State private var isFetchingRate = false
    @State private var rateFetchError: String?
    @State private var rateFetchInfo: String?

    @State private var isConfirmingDelete = false

    private static let popularCurrencies = [
        "PLN", "USD", "EUR", "GBP", "CHF", "JPY",
        "CZK", "NOK", "SEK", "DKK", "HUF", "UAH"
    ]

    init(assetToEdit: Asset?) {
        self.assetToEdit = assetToEdit
        if let asset = assetToEdit {
            _name = State(initialValue: asset.name)
            _ticker = State(initialValue: asset.ticker ?? "")
            _type = State(initialValue: asset.type)
            _quantityText = State(initialValue: String(asset.quantity))
            _purchasePriceText = State(initialValue: String(asset.purchasePrice))
            _purchaseDate = State(initialValue: asset.purchaseDate)
            _manualPriceText = State(initialValue: asset.manualCurrentPrice.map { String($0) } ?? "")
            _currency = State(initialValue: asset.currency ?? "PLN")
            _purchaseCurrency = State(initialValue: asset.purchaseCurrency ?? "USD")
            _isEDO = State(initialValue: asset.type != .bond || asset.bondSeries != nil)
            _bondSeriesText = State(initialValue: asset.bondSeries ?? "")
            _firstYearRateText = State(initialValue: Self.percentText(asset.bondFirstYearRate))
            _marginText = State(initialValue: Self.percentText(asset.bondMargin))
            _inflationText = State(initialValue: Self.percentText(asset.bondInflation))
            _bondRateFetchDate = State(initialValue: asset.bondRateFetchDate)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Podstawowe informacje") {
                    TextField("Nazwa (np. Apple Inc.)", text: $name)

                    Picker("Klasa aktywa", selection: $type) {
                        ForEach(AssetType.allCases) { assetType in
                            Text(assetType.rawValue).tag(assetType)
                        }
                    }

                    if type == .cash {
                        Picker("Waluta", selection: $currency) {
                            ForEach(Self.popularCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        Text(currency == "USD"
                             ? "Wartość gotówki w USD bez przeliczania."
                             : "Kurs \(currency)/USD zostanie pobrany automatycznie przy odświeżeniu cen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if type.autoFetchesPrice {
                        TextField("Ticker", text: $ticker)
                        Text(type.tickerHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(type == .cash ? "Ilość" : "Ilość i cena zakupu") {
                    TextField(
                        type == .cash ? "Ilość gotówki"
                            : (type == .gold || type == .silver) ? "Ilość uncji"
                            : type == .bond ? "Liczba obligacji"
                            : "Ilość jednostek",
                        text: $quantityText
                    )
                    if type != .cash {
                        TextField(
                            (type == .gold || type == .silver) ? "Cena zakupu za uncję"
                                : type == .bond ? "Cena zakupu jednej obligacji (np. 100)"
                                : "Cena zakupu za jednostkę",
                            text: $purchasePriceText
                        )
                        Picker("Waluta zakupu", selection: $purchaseCurrency) {
                            ForEach(Self.popularCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        if purchaseCurrency != "USD" {
                            Text("Kwota zostanie przeliczona na USD przy odświeżeniu cen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Data zakupu", selection: $purchaseDate, displayedComponents: .date)
                }

                if type == .bond {
                    bondSection
                }

                if type.autoFetchesPrice || type == .gold || type == .silver {
                    manualPriceSection
                }
            }
            .formStyle(.grouped)
            .onChange(of: type) { _, newType in
                // Obligacje skarbowe kupuje się w PLN po 100 zł - podpowiadamy to przy nowym aktywie.
                guard newType == .bond, assetToEdit == nil else { return }
                purchaseCurrency = "PLN"
                if purchasePriceText.isEmpty { purchasePriceText = "100" }
                if bondSeriesText.isEmpty { bondSeriesText = EDOSeries.code(forPurchaseDate: purchaseDate) }
            }
            .onChange(of: purchaseDate) { oldDate, newDate in
                // Jeśli seria była wyliczona z poprzedniej daty, aktualizujemy ją razem z datą.
                if bondSeriesText.isEmpty || bondSeriesText == EDOSeries.code(forPurchaseDate: oldDate) {
                    bondSeriesText = EDOSeries.code(forPurchaseDate: newDate)
                }
            }

            Divider()

            HStack {
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if assetToEdit != nil {
                    Button("Usuń", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .confirmationDialog(
                        "Usunąć pozycję?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Usuń", role: .destructive) {
                            if let asset = assetToEdit {
                                store.deleteAsset(asset)
                            }
                            dismiss()
                        }
                        Button("Anuluj", role: .cancel) {}
                    } message: {
                        Text("\(assetToEdit?.name ?? "Pozycja") - tej operacji nie można cofnąć.")
                    }
                }

                Button(assetToEdit == nil ? "Dodaj" : "Zapisz") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(quantityText.replacingOccurrences(of: ",", with: ".")) != nil
            && (type == .cash || Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) != nil)
            && (type == .cash || isEmptyOrNumber(manualPriceText))
            && (type != .bond || bondFieldsAreValid)
    }

    private func isEmptyOrNumber(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || Self.parseNumber(text) != nil
    }

    /// Pola obligacji są opcjonalne, ale jeśli coś wpisano, musi to być poprawna wartość.
    private var bondFieldsAreValid: Bool {
        guard isEDO else { return true }
        let seriesOK = bondSeriesText.trimmingCharacters(in: .whitespaces).isEmpty
            || EDOSeries.normalize(bondSeriesText) != nil
        return seriesOK && [firstYearRateText, marginText, inflationText].allSatisfy(isEmptyOrNumber)
    }

    // MARK: - Obligacje EDO

    private var bondSection: some View {
        Section("Obligacje") {
            Toggle("Obligacje skarbowe EDO (10-letnie, indeksowane inflacją)", isOn: $isEDO)

            if isEDO {
                HStack {
                    TextField("Seria (np. EDO0936)", text: $bondSeriesText)
                    Button("Z daty zakupu") {
                        bondSeriesText = EDOSeries.code(forPurchaseDate: purchaseDate)
                    }
                    .help("Seria = EDO + miesiąc i rok wykupu (zakup + 10 lat)")
                }
                if !bondSeriesText.isEmpty && EDOSeries.normalize(bondSeriesText) == nil {
                    Text("Nieprawidłowy kod serii. Format: EDOMMRR, np. EDO0936 (sprzedaż 09.2026, wykup 09.2036).")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button {
                        fetchBondRate()
                    } label: {
                        Label("Pobierz oprocentowanie", systemImage: "arrow.down.circle")
                    }
                    .disabled(isFetchingRate || EDOSeries.normalize(bondSeriesText) == nil)
                    if isFetchingRate {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Text("Źródło: obligacjeskarbowe.pl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rateFetchError {
                    Text(rateFetchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let rateFetchInfo {
                    Text(rateFetchInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Oprocentowanie w 1. roku (%)", text: $firstYearRateText)
                TextField("Marża od 2. roku (%)", text: $marginText)
                TextField("Inflacja dla bieżącego okresu (%)", text: $inflationText)
                Text("Od 2. roku oprocentowanie = marża + inflacja r/r ogłoszona przez GUS w miesiącu przed początkiem okresu odsetkowego. Inflację wpisz ręcznie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let rate = currentBondRatePreview {
                    Text("Aktualne oprocentowanie: \(Self.percentText(rate))%")
                        .font(.callout.bold())
                }
            }

            TextField("Aktualna wartość jednej obligacji (\(purchaseCurrency))", text: $manualPriceText)
            Text("Opcjonalnie - np. wartość z konta w PKO BP. Puste = wycena po cenie zakupu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Cena ręczna dla aktywów wycenianych automatycznie (akcje, ETF-y, krypto, złoto, srebro).
    /// Podawana - tak jak cena zakupu i wartość obligacji - w walucie zakupu; przy wycenie
    /// przeliczana na USD tym samym kursem co koszt nabycia.
    private var manualPriceSection: some View {
        Section("Cena ręczna (opcjonalnie)") {
            TextField(
                (type == .gold || type == .silver)
                    ? "Aktualna cena za uncję (\(purchaseCurrency))"
                    : "Aktualna cena za jednostkę (\(purchaseCurrency))",
                text: $manualPriceText
            )
            Text("Używana, gdy nie ma pobranej ceny (np. brak internetu albo błędny ticker). Cena pobrana automatycznie ma pierwszeństwo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentBondRatePreview: Double? {
        EDOSeries.currentRate(
            purchaseDate: purchaseDate,
            firstYearRate: Self.parseNumber(firstYearRateText),
            margin: Self.parseNumber(marginText),
            inflation: Self.parseNumber(inflationText)
        )
    }

    private func fetchBondRate() {
        guard let code = EDOSeries.normalize(bondSeriesText) else { return }
        bondSeriesText = code
        rateFetchError = nil
        rateFetchInfo = nil
        isFetchingRate = true

        Task {
            defer { isFetchingRate = false }
            do {
                let result = try await BondRateService.shared.rate(for: code)
                firstYearRateText = Self.percentText(result.firstYearRate)
                if let margin = result.margin {
                    marginText = Self.percentText(margin)
                    rateFetchInfo = "Pobrano oprocentowanie serii \(code)."
                } else {
                    rateFetchInfo = "Pobrano oprocentowanie serii \(code). Strona nie podaje marży - wpisz ją ręcznie (z listu emisyjnego)."
                }
                bondRateFetchDate = result.fetchedAt
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = "Obligacje skarbowe \(code)"
                }
            } catch {
                rateFetchError = error.localizedDescription
            }
        }
    }

    private static func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let purchasePrice = type == .cash
            ? 1.0
            : (Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let manualPrice = Self.parseNumber(manualPriceText)

        var asset = assetToEdit ?? Asset(
            name: "",
            ticker: nil,
            type: .stock,
            quantity: 0,
            purchasePrice: 0,
            purchaseDate: Date()
        )

        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces)
        let newPurchaseCurrency = (type != .cash && purchaseCurrency != "USD") ? purchaseCurrency : nil

        asset.name = name.trimmingCharacters(in: .whitespaces)
        asset.ticker = trimmedTicker.isEmpty ? nil : trimmedTicker
        asset.type = type
        asset.quantity = quantity
        asset.purchasePrice = purchasePrice
        asset.purchaseDate = purchaseDate
        // Dla gotówki pole ceny ręcznej nie jest pokazywane (tam oznacza kurs do USD),
        // więc nie przenosimy do niej ceny wpisanej wcześniej dla innej klasy aktywa.
        if type == .cash {
            if assetToEdit?.type != .cash { asset.manualCurrentPrice = nil }
        } else {
            asset.manualCurrentPrice = manualPrice
        }
        asset.currency = type == .cash ? currency : nil
        // Po zmianie waluty zakupu stary kurs jest nieaktualny (np. PLN->USD zostawiało kurs 0,27
        // i zaniżało koszt nabycia). Nowy kurs zostanie pobrany przy odświeżeniu cen.
        if asset.purchaseCurrency != newPurchaseCurrency {
            asset.purchaseCurrencyRate = nil
        }
        asset.purchaseCurrency = newPurchaseCurrency

        if type == .bond && isEDO {
            asset.bondSeries = EDOSeries.normalize(bondSeriesText)
            asset.bondFirstYearRate = Self.parseNumber(firstYearRateText)
            asset.bondMargin = Self.parseNumber(marginText)
            asset.bondInflation = Self.parseNumber(inflationText)
            asset.bondRateFetchDate = bondRateFetchDate
        } else {
            asset.bondSeries = nil
            asset.bondFirstYearRate = nil
            asset.bondMargin = nil
            asset.bondInflation = nil
            asset.bondRateFetchDate = nil
        }

        if assetToEdit != nil {
            store.updateAsset(asset)
        } else {
            store.addAsset(asset)
        }

        dismiss()
    }
}

#Preview {
    AddAssetView(assetToEdit: nil)
        .environmentObject(PortfolioStore())
}
