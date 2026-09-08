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
                            : "Ilość jednostek",
                        text: $quantityText
                    )
                    if type != .cash {
                        TextField(
                            (type == .gold || type == .silver) ? "Cena zakupu za uncję" : "Cena zakupu za jednostkę",
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


            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if assetToEdit != nil {
                    Button("Usuń", role: .destructive) {
                        if let asset = assetToEdit {
                            store.deleteAsset(asset)
                        }
                        dismiss()
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
    }

    private func save() {
        let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let purchasePrice = type == .cash
            ? 1.0
            : (Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let manualPrice = Double(manualPriceText.replacingOccurrences(of: ",", with: "."))

        var asset = assetToEdit ?? Asset(
            name: "",
            ticker: nil,
            type: .stock,
            quantity: 0,
            purchasePrice: 0,
            purchaseDate: Date()
        )

        asset.name = name.trimmingCharacters(in: .whitespaces)
        asset.ticker = ticker.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ticker
        asset.type = type
        asset.quantity = quantity
        asset.purchasePrice = purchasePrice
        asset.purchaseDate = purchaseDate
        asset.manualCurrentPrice = manualPrice
        asset.currency = type == .cash ? currency : nil
        asset.purchaseCurrency = (type != .cash && purchaseCurrency != "USD") ? purchaseCurrency : nil

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
