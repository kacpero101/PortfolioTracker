//
//  AddAssetView.swift
//  PortfolioTracker
//
//  Formularz zakupu (nowa pozycja albo kolejna transza) oraz edycji pozycji.
//  - `.newPurchase`: instrument + pierwsza transza; jeśli instrument już jest w portfelu,
//    zakup trafia jako nowa transza do istniejącej pozycji.
//  - `.addLot(to:)`: kolejna transza do wskazanej pozycji (instrument tylko do odczytu).
//  - `.editPosition`: pola instrumentu (nazwa, ticker, cena ręczna, obligacje) - bez transz.
//

import SwiftUI

enum AssetFormMode {
    case newPurchase
    case addLot(to: Asset)
    case editPosition(Asset)

    var position: Asset? {
        switch self {
        case .newPurchase: return nil
        case .addLot(let asset), .editPosition(let asset): return asset
        }
    }
}

struct AddAssetView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    let mode: AssetFormMode
    /// Wywoływane po zapisie z komunikatem dla użytkownika (np. „Dodano transzę do istniejącej pozycji BTC”).
    var onFinished: ((String?) -> Void)?

    // Pola formularza - trzymane osobno, żeby łatwo je walidować i wiązać z UI.
    @State private var name: String = ""
    @State private var ticker: String = ""
    @State private var type: AssetType = .stock
    @State private var quantityText: String = ""
    @State private var purchasePriceText: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var lotNote: String = ""
    @State private var manualPriceText: String = ""
    @State private var manualPriceCurrency: String = "USD"
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

    static let popularCurrencies = [
        "PLN", "USD", "EUR", "GBP", "CHF", "JPY",
        "CZK", "NOK", "SEK", "DKK", "HUF", "UAH"
    ]

    init(mode: AssetFormMode, onFinished: ((String?) -> Void)? = nil) {
        self.mode = mode
        self.onFinished = onFinished
        if let asset = mode.position {
            _name = State(initialValue: asset.name)
            _ticker = State(initialValue: asset.ticker ?? "")
            _type = State(initialValue: asset.type)
            _manualPriceText = State(initialValue: asset.manualCurrentPrice.map { Self.numberText($0) } ?? "")
            _manualPriceCurrency = State(initialValue: asset.manualPriceCurrency?.uppercased()
                                         ?? asset.commonPurchaseCurrency ?? "USD")
            _currency = State(initialValue: asset.currency ?? "PLN")
            // Nowa transza: domyślnie waluta ostatniego zakupu.
            _purchaseCurrency = State(initialValue: asset.lots.last?.displayCurrency ?? "USD")
            _isEDO = State(initialValue: asset.type != .bond || asset.bondSeries != nil)
            _bondSeriesText = State(initialValue: asset.bondSeries ?? "")
            _firstYearRateText = State(initialValue: Self.percentText(asset.bondFirstYearRate))
            _marginText = State(initialValue: Self.percentText(asset.bondMargin))
            _inflationText = State(initialValue: Self.percentText(asset.bondInflation))
            _bondRateFetchDate = State(initialValue: asset.bondRateFetchDate)
            if asset.type == .bond, case .addLot = mode {
                _purchasePriceText = State(initialValue: "100")
            }
        }
    }

    private var isEditingPosition: Bool {
        if case .editPosition = mode { return true }
        return false
    }

    private var isAddingLot: Bool {
        if case .addLot = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if isAddingLot, let position = mode.position {
                    Section("Nowa transza") {
                        LabeledContent("Pozycja", value: position.name)
                        LabeledContent("Klasa aktywa", value: position.type.rawValue)
                        if let ticker = position.ticker, !ticker.isEmpty {
                            LabeledContent("Ticker", value: ticker.uppercased())
                        }
                        if let series = position.bondSeries {
                            LabeledContent("Seria", value: series)
                        }
                    }
                } else {
                    instrumentSection
                }

                if !isEditingPosition {
                    lotSection
                }

                if type == .bond && !isAddingLot {
                    bondSection
                }

                if !isAddingLot && (type.autoFetchesPrice || type == .gold || type == .silver) {
                    manualPriceSection
                }
            }
            .formStyle(.grouped)
            .onChange(of: type) { _, newType in
                // Obligacje skarbowe kupuje się w PLN po 100 zł - podpowiadamy to przy nowym zakupie.
                guard newType == .bond, case .newPurchase = mode else { return }
                purchaseCurrency = "PLN"
                if purchasePriceText.isEmpty { purchasePriceText = "100" }
                if bondSeriesText.isEmpty { bondSeriesText = EDOSeries.code(forPurchaseDate: purchaseDate) }
            }
            .onChange(of: purchaseDate) { oldDate, newDate in
                // Jeśli seria była wyliczona z poprzedniej daty, aktualizujemy ją razem z datą.
                guard case .newPurchase = mode else { return }
                if bondSeriesText.isEmpty || bondSeriesText == EDOSeries.code(forPurchaseDate: oldDate) {
                    bondSeriesText = EDOSeries.code(forPurchaseDate: newDate)
                }
            }
            .onChange(of: purchaseCurrency) { _, newCurrency in
                // Przy nowym zakupie cena ręczna jest domyślnie w walucie zakupu.
                guard case .newPurchase = mode else { return }
                manualPriceCurrency = newCurrency
            }

            Divider()

            HStack {
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if case .editPosition(let position) = mode {
                    Button("Usuń pozycję", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .confirmationDialog(
                        "Usunąć całą pozycję?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Usuń", role: .destructive) {
                            store.deletePosition(position)
                            dismiss()
                        }
                        Button("Anuluj", role: .cancel) {}
                    } message: {
                        Text("\(position.name) - zostanie usunięte \(position.lots.count) transz(e). Tej operacji nie można cofnąć.")
                    }
                }

                Button(saveButtonTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 440)
    }

    private var saveButtonTitle: String {
        switch mode {
        case .newPurchase: return "Dodaj"
        case .addLot: return "Dodaj transzę"
        case .editPosition: return "Zapisz"
        }
    }

    // MARK: - Sekcje

    private var instrumentSection: some View {
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

            if let existing = existingPositionHint {
                Label(existing, systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    /// Podpowiedź, że zakup trafi do istniejącej pozycji (albo że edycja ją scali).
    private var existingPositionHint: String? {
        let candidate = instrumentFromFields(base: mode.position)
        guard let existing = store.existingPosition(matching: candidate) else { return nil }
        if isEditingPosition {
            return "Po zapisie ta pozycja zostanie scalona z istniejącą pozycją „\(existing.name)”."
        }
        return "„\(existing.name)” jest już w portfelu - zakup zostanie dodany jako nowa transza tej pozycji."
    }

    private var lotSection: some View {
        Section(type == .cash ? "Kwota" : "Ilość i cena zakupu") {
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
            TextField("Notatka (opcjonalnie)", text: $lotNote)
        }
    }

    private var bondSection: some View {
        Section("Obligacje") {
            Toggle("Obligacje skarbowe EDO (10-letnie, indeksowane inflacją)", isOn: $isEDO)

            if isEDO {
                HStack {
                    TextField("Seria (np. EDO0936)", text: $bondSeriesText)
                    if !isEditingPosition {
                        Button("Z daty zakupu") {
                            bondSeriesText = EDOSeries.code(forPurchaseDate: purchaseDate)
                        }
                        .help("Seria = EDO + miesiąc i rok wykupu (zakup + 10 lat)")
                    }
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
                Text("Jeśli pola zostaną puste, oprocentowanie zostanie pobrane automatycznie po zapisie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            HStack {
                TextField("Aktualna wartość jednej obligacji", text: $manualPriceText)
                currencyPicker(selection: $manualPriceCurrency)
            }
            Text("Opcjonalnie - np. wartość z konta w PKO BP. Puste = wycena po cenie zakupu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Cena ręczna dla pozycji wycenianych automatycznie (akcje, ETF-y, krypto, złoto, srebro).
    private var manualPriceSection: some View {
        Section("Cena ręczna (opcjonalnie)") {
            HStack {
                TextField(
                    (type == .gold || type == .silver)
                        ? "Aktualna cena za uncję"
                        : "Aktualna cena za jednostkę",
                    text: $manualPriceText
                )
                currencyPicker(selection: $manualPriceCurrency)
            }
            Text("Używana, gdy nie ma pobranej ceny (np. brak internetu albo błędny ticker). Cena pobrana automatycznie ma pierwszeństwo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func currencyPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(Self.popularCurrencies, id: \.self) { code in
                Text(code).tag(code)
            }
        }
        .labelsHidden()
        .frame(width: 80)
    }

    // MARK: - Walidacja

    private var isValid: Bool {
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let lotOK = isEditingPosition
            || ((Self.parseNumber(quantityText) ?? 0) > 0
                && (type == .cash || Self.parseNumber(purchasePriceText) != nil))
        return nameOK && lotOK
            && (type == .cash || isEmptyOrNumber(manualPriceText))
            && (type != .bond || isAddingLot || bondFieldsAreValid)
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

    private var currentBondRatePreview: Double? {
        EDOSeries.currentRate(
            purchaseDate: mode.position?.firstPurchaseDate ?? purchaseDate,
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

    // MARK: - Formatowanie liczb

    static func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func numberText(_ value: Double) -> String {
        var text = String(value)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Zapis

    /// Pozycja zbudowana z pól instrumentu (bez zmiany transz `base`).
    private func instrumentFromFields(base: Asset?) -> Asset {
        var asset = base ?? Asset(name: "", type: .stock)
        if isAddingLot { return asset }

        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces)
        asset.name = name.trimmingCharacters(in: .whitespaces)
        asset.ticker = (type.autoFetchesPrice && !trimmedTicker.isEmpty) ? trimmedTicker : nil
        asset.type = type
        asset.currency = type == .cash ? currency : nil

        // Dla gotówki pole ceny ręcznej nie jest pokazywane (tam oznacza kurs do USD).
        if type == .cash {
            asset.manualCurrentPrice = nil
            asset.manualPriceCurrency = nil
            asset.manualPriceCurrencyRate = nil
        } else {
            let manualPrice = Self.parseNumber(manualPriceText)
            let newCurrency: String? = (manualPrice != nil && manualPriceCurrency != "USD") ? manualPriceCurrency : nil
            // Po zmianie waluty stary kurs jest nieaktualny - nowy pobierze odświeżenie cen.
            if asset.manualPriceCurrency?.uppercased() != newCurrency {
                asset.manualPriceCurrencyRate = nil
            }
            asset.manualCurrentPrice = manualPrice
            asset.manualPriceCurrency = newCurrency
        }

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
        return asset
    }

    private func lotFromFields() -> PurchaseLot {
        let quantity = Self.parseNumber(quantityText) ?? 0
        let note = lotNote.trimmingCharacters(in: .whitespaces)
        if type == .cash {
            return PurchaseLot(date: purchaseDate, quantity: quantity, price: 1.0, note: note.isEmpty ? nil : note)
        }
        return PurchaseLot(
            date: purchaseDate,
            quantity: quantity,
            price: Self.parseNumber(purchasePriceText) ?? 0,
            purchaseCurrency: purchaseCurrency == "USD" ? nil : purchaseCurrency,
            // Kurs z dnia zakupu zostanie pobrany przy odświeżeniu cen.
            purchaseCurrencyRate: nil,
            note: note.isEmpty ? nil : note
        )
    }

    private func save() {
        var message: String?
        switch mode {
        case .editPosition(let original):
            // Bieżąca wersja z magazynu - odświeżenie cen mogło w międzyczasie zmienić kursy transz.
            let position = store.assets.first { $0.id == original.id } ?? original
            var asset = instrumentFromFields(base: position)
            if asset.type != position.type {
                // Gotówka ma transze z ceną 1 bez waluty - przy zmianie klasy zostawiamy transze bez zmian.
                asset.fetchedPrice = nil
                asset.lastPriceUpdate = nil
            }
            if asset.type == .cash && position.currency != asset.currency {
                asset.fetchedPrice = nil
            }
            if Asset.normalizedTicker(asset.ticker, type: asset.type)
                != Asset.normalizedTicker(position.ticker, type: position.type) {
                // Stara cena dotyczyła innego tickera.
                asset.fetchedPrice = nil
                asset.lastPriceUpdate = nil
            }
            store.updatePosition(asset)
        case .newPurchase, .addLot:
            var asset = instrumentFromFields(base: mode.position)
            if case .newPurchase = mode { asset.id = UUID() }
            asset.lots = [lotFromFields()]
            let result = store.addPurchase(asset)
            // Przy jawnym „Dodaj transzę” użytkownik wie, dokąd trafia zakup - komunikat tylko dla „+”.
            if case .newPurchase = mode, case .addedLot(let position) = result {
                message = "Dodano transzę do istniejącej pozycji \(position.name)."
            }
        }
        onFinished?(message)
        dismiss()
    }
}

#Preview {
    AddAssetView(mode: .newPurchase)
        .environmentObject(PortfolioStore())
}
