//
//  LotEditView.swift
//  PortfolioTracker
//
//  Edycja pojedynczej transzy zakupu (data, ilość, cena, waluta, notatka) oraz jej usuwanie.
//

import SwiftUI

struct LotEditView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    let position: Asset
    let lot: PurchaseLot

    @State private var date: Date
    @State private var quantityText: String
    @State private var priceText: String
    @State private var purchaseCurrency: String
    @State private var note: String
    @State private var isConfirmingDelete = false

    init(position: Asset, lot: PurchaseLot) {
        self.position = position
        self.lot = lot
        _date = State(initialValue: lot.date)
        _quantityText = State(initialValue: AddAssetView.numberText(lot.quantity))
        _priceText = State(initialValue: AddAssetView.numberText(lot.price))
        _purchaseCurrency = State(initialValue: lot.displayCurrency)
        _note = State(initialValue: lot.note ?? "")
    }

    private var isCash: Bool { position.type == .cash }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Transza - \(position.name)") {
                    DatePicker("Data zakupu", selection: $date, displayedComponents: .date)
                    TextField(isCash ? "Kwota" : "Ilość", text: $quantityText)
                    if !isCash {
                        TextField("Cena zakupu za jednostkę", text: $priceText)
                        Picker("Waluta zakupu", selection: $purchaseCurrency) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        if purchaseCurrency != "USD" {
                            Text(rateDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Notatka (opcjonalnie)", text: $note)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Usuń transzę", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog(
                    isLastLot ? "Usunąć ostatnią transzę i całą pozycję?" : "Usunąć transzę?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Usuń", role: .destructive) {
                        store.deleteLot(id: lot.id, fromPosition: position.id)
                        dismiss()
                    }
                    Button("Anuluj", role: .cancel) {}
                } message: {
                    Text(deleteMessage)
                }
                Button("Zapisz") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var currencies: [String] {
        var list = AddAssetView.popularCurrencies
        if !list.contains(purchaseCurrency) { list.append(purchaseCurrency) }
        return list
    }

    private var isLastLot: Bool {
        (store.assets.first { $0.id == position.id }?.lots.count ?? position.lots.count) <= 1
    }

    private var deleteMessage: String {
        let summary = "\(date.formatted(date: .abbreviated, time: .omitted)), ilość \(quantityText)"
        if isLastLot {
            return "\(summary) - to jedyna transza pozycji \(position.name), więc pozycja zostanie usunięta. Tej operacji nie można cofnąć."
        }
        return "\(summary) - tej operacji nie można cofnąć."
    }

    private var rateDescription: String {
        if purchaseCurrency == lot.displayCurrency, let rate = lot.purchaseCurrencyRate {
            return String(format: "Kurs %@/USD: %.4f (aktualizowany przy odświeżeniu cen).", purchaseCurrency, rate)
        }
        return "Kurs \(purchaseCurrency)/USD zostanie pobrany przy odświeżeniu cen."
    }

    private var isValid: Bool {
        (AddAssetView.parseNumber(quantityText) ?? 0) > 0
            && (isCash || AddAssetView.parseNumber(priceText) != nil)
    }

    private func save() {
        var updated = lot
        updated.date = date
        updated.quantity = AddAssetView.parseNumber(quantityText) ?? lot.quantity
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        updated.note = trimmedNote.isEmpty ? nil : trimmedNote
        if !isCash {
            updated.price = AddAssetView.parseNumber(priceText) ?? lot.price
            let newCurrency: String? = purchaseCurrency == "USD" ? nil : purchaseCurrency
            if newCurrency != lot.purchaseCurrency?.uppercased() {
                updated.purchaseCurrency = newCurrency
                updated.purchaseCurrencyRate = nil
            }
        }
        // Brakujący kurs nowej waluty pobierze odświeżenie uruchamiane przez store po zmianie.
        store.updateLot(updated, inPosition: position.id)
        dismiss()
    }
}
