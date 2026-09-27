//
//  AssetsView.swift
//  PortfolioTracker
//
//  Lista pozycji w portfelu (jedna na instrument). Kliknięcie rozwija listę transz zakupu,
//  gdzie można dodać kolejną transzę, edytować/usunąć transzę albo edytować/usunąć pozycję.
//

import SwiftUI

struct AssetsView: View {
    @EnvironmentObject private var store: PortfolioStore

    /// Arkusz aktualnie pokazywany nad listą.
    private enum ActiveSheet: Identifiable {
        case newPurchase
        case addLot(Asset)
        case editPosition(Asset)
        case editLot(Asset, PurchaseLot)

        var id: String {
            switch self {
            case .newPurchase: return "new"
            case .addLot(let asset): return "addLot-\(asset.id)"
            case .editPosition(let asset): return "edit-\(asset.id)"
            case .editLot(let asset, let lot): return "lot-\(asset.id)-\(lot.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var expanded: Set<UUID> = []
    /// Pozycje wskazane do usunięcia - czekają na potwierdzenie.
    @State private var positionsPendingDeletion: [Asset] = []
    /// Transza wskazana do usunięcia (pozycja, transza) - czeka na potwierdzenie.
    @State private var lotPendingDeletion: (position: Asset, lot: PurchaseLot)?
    /// Komunikat po dodaniu zakupu (np. „Dodano transzę do istniejącej pozycji BTC”).
    @State private var infoMessage: String?

    var body: some View {
        VStack {
            if let infoMessage {
                HStack {
                    Label(infoMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button {
                        self.infoMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            if store.assets.isEmpty {
                ContentUnavailableView(
                    "Brak aktywów",
                    systemImage: "tray",
                    description: Text("Dodaj pierwszą pozycję przyciskiem „+” powyżej.")
                )
            } else {
                List {
                    ForEach(store.assets) { asset in
                        VStack(alignment: .leading, spacing: 8) {
                            PositionRow(asset: asset, isExpanded: expanded.contains(asset.id))
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(asset) }
                            if expanded.contains(asset.id) {
                                lotsDetail(for: asset)
                            }
                        }
                        .contextMenu {
                            Button("Dodaj transzę") { activeSheet = .addLot(asset) }
                            Button("Edytuj pozycję") { activeSheet = .editPosition(asset) }
                            Divider()
                            Button("Usuń pozycję", role: .destructive) { positionsPendingDeletion = [asset] }
                        }
                    }
                    .onDelete { offsets in
                        // Zapamiętujemy pozycje (a nie indeksy), bo lista może się zmienić,
                        // zanim użytkownik potwierdzi usunięcie.
                        positionsPendingDeletion = offsets.map { store.assets[$0] }
                    }
                }
                .confirmationDialog(
                    positionDeletionTitle,
                    isPresented: Binding(
                        get: { !positionsPendingDeletion.isEmpty },
                        set: { if !$0 { positionsPendingDeletion = [] } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Usuń", role: .destructive) {
                        positionsPendingDeletion.forEach(store.deletePosition)
                        positionsPendingDeletion = []
                    }
                    Button("Anuluj", role: .cancel) {
                        positionsPendingDeletion = []
                    }
                } message: {
                    Text(positionDeletionMessage)
                }
                .confirmationDialog(
                    lotDeletionTitle,
                    isPresented: Binding(
                        get: { lotPendingDeletion != nil },
                        set: { if !$0 { lotPendingDeletion = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Usuń", role: .destructive) {
                        if let pending = lotPendingDeletion {
                            store.deleteLot(id: pending.lot.id, fromPosition: pending.position.id)
                        }
                        lotPendingDeletion = nil
                    }
                    Button("Anuluj", role: .cancel) {
                        lotPendingDeletion = nil
                    }
                } message: {
                    Text(lotDeletionMessage)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .newPurchase
                } label: {
                    Label("Dodaj aktywo", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newPurchase:
                AddAssetView(mode: .newPurchase) { message in
                    infoMessage = message
                }
            case .addLot(let asset):
                AddAssetView(mode: .addLot(to: asset))
            case .editPosition(let asset):
                AddAssetView(mode: .editPosition(asset))
            case .editLot(let asset, let lot):
                LotEditView(position: asset, lot: lot)
            }
        }
    }

    private func toggle(_ asset: Asset) {
        if expanded.contains(asset.id) {
            expanded.remove(asset.id)
        } else {
            expanded.insert(asset.id)
        }
    }

    // MARK: - Szczegóły pozycji (transze)

    @ViewBuilder
    private func lotsDetail(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transze (\(asset.lots.count))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(asset.lots) { lot in
                LotRow(asset: asset, lot: lot) {
                    activeSheet = .editLot(asset, lot)
                } onDelete: {
                    lotPendingDeletion = (asset, lot)
                }
            }

            HStack {
                Button {
                    activeSheet = .addLot(asset)
                } label: {
                    Label("Dodaj transzę", systemImage: "plus.circle")
                }
                Button {
                    activeSheet = .editPosition(asset)
                } label: {
                    Label("Edytuj pozycję", systemImage: "pencil")
                }
                Spacer()
                Button(role: .destructive) {
                    positionsPendingDeletion = [asset]
                } label: {
                    Label("Usuń pozycję", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(.leading, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Teksty potwierdzeń

    private var positionDeletionTitle: String {
        positionsPendingDeletion.count > 1 ? "Usunąć zaznaczone pozycje?" : "Usunąć całą pozycję?"
    }

    private var positionDeletionMessage: String {
        let names = positionsPendingDeletion
            .map { "\($0.name) (transze: \($0.lots.count))" }
            .joined(separator: ", ")
        return "\(names) - tej operacji nie można cofnąć."
    }

    private var lotDeletionTitle: String {
        guard let pending = lotPendingDeletion else { return "Usunąć transzę?" }
        return pending.position.lots.count <= 1 ? "Usunąć ostatnią transzę i całą pozycję?" : "Usunąć transzę?"
    }

    private var lotDeletionMessage: String {
        guard let pending = lotPendingDeletion else { return "" }
        let summary = "\(pending.position.name): \(pending.lot.date.formatted(date: .abbreviated, time: .omitted)), ilość \(Formatters.quantity(pending.lot.quantity))"
        if pending.position.lots.count <= 1 {
            return "\(summary). To jedyna transza, więc pozycja zostanie usunięta. Tej operacji nie można cofnąć."
        }
        return "\(summary). Tej operacji nie można cofnąć."
    }
}

// MARK: - Formatowanie

enum Formatters {
    /// Ilość bez zbędnych zer (np. 3, 0,00677862).
    static func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }

    static func money(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency))
    }

    static func usd(_ value: Double) -> String {
        money(value, currency: "USD")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }
}

// MARK: - Wiersz pozycji

/// Pojedynczy wiersz pozycji: łączna ilość, średnia cena, wartość i zysk/strata.
private struct PositionRow: View {
    let asset: Asset
    let isExpanded: Bool
    @EnvironmentObject private var colorStore: AssetColorStore
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        HStack {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorStore.color(for: asset.type))
                        .frame(width: 8, height: 8)
                    Text(asset.name)
                        .font(.headline)
                    if let ticker = asset.ticker, !ticker.isEmpty {
                        Text(ticker.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if asset.lots.count > 1 {
                        Text("\(asset.lots.count) transze")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let series = asset.bondSeries {
                    Text(bondRateDescription(series: series))
                        .font(.caption)
                        .foregroundStyle(bondRateFailed ? .orange : .secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.usd(asset.currentValue))
                    .font(.headline)
                if asset.type != .cash {
                    Text("\(Formatters.usd(asset.profitLoss)) (\(Formatters.percent(asset.profitLossPercent)))")
                        .font(.caption)
                        .foregroundStyle(asset.profitLoss >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Np. "Kryptowaluty · ilość: 0,00719206 · śr. cena 68 000,00 €".
    private var detailLine: String {
        var parts = [asset.type.rawValue]
        if asset.type == .cash {
            let code = (asset.currency ?? "USD").uppercased()
            parts.append("kwota: \(Formatters.money(asset.quantity, currency: code))")
        } else {
            parts.append("ilość: \(Formatters.quantity(asset.quantity))")
            if let code = asset.commonPurchaseCurrency, let avg = asset.averagePurchasePriceInCommonCurrency {
                parts.append("śr. cena \(Formatters.money(avg, currency: code))")
            } else {
                parts.append("śr. cena \(Formatters.usd(asset.averagePurchasePriceUSD))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var bondRateFailed: Bool {
        asset.currentBondRate == nil && store.bondRateFetchFailures[asset.id] != nil
    }

    /// Np. "EDO0936 · oprocentowanie 5.35% · marża 2.00%".
    private func bondRateDescription(series: String) -> String {
        var parts = [series]
        if let rate = asset.currentBondRate {
            parts.append(String(format: "oprocentowanie %.2f%%", rate))
        } else if bondRateFailed {
            parts.append("oprocentowanie: nie pobrano – edytuj, aby wpisać ręcznie")
        } else if asset.needsBondRateFetch {
            parts.append("oprocentowanie: pobieranie przy odświeżeniu cen…")
        } else {
            parts.append("oprocentowanie: brak danych (od 2. roku wpisz inflację)")
        }
        if let margin = asset.bondMargin {
            parts.append(String(format: "marża %.2f%%", margin))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Wiersz transzy

private struct LotRow: View {
    let asset: Asset
    let lot: PurchaseLot
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(lot.date.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(quantityAndPrice)
                if let note = lot.note, !note.isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.usd(asset.currentValue(of: lot)))
                if asset.type != .cash {
                    let pl = asset.profitLoss(of: lot)
                    Text("\(Formatters.usd(pl)) (\(Formatters.percent(asset.profitLossPercent(of: lot))))")
                        .foregroundStyle(pl >= 0 ? .green : .red)
                }
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edytuj transzę")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Usuń transzę")
        }
        .font(.caption)
        .padding(.vertical, 2)
    }

    private var quantityAndPrice: String {
        if asset.type == .cash {
            return Formatters.money(lot.quantity, currency: (asset.currency ?? "USD").uppercased())
        }
        var text = "\(Formatters.quantity(lot.quantity)) × \(Formatters.money(lot.price, currency: lot.displayCurrency))"
        if lot.displayCurrency != "USD" {
            if let rate = lot.purchaseCurrencyRate {
                text += String(format: " (kurs %.4f → %@)", rate, Formatters.usd(lot.costBasisUSD))
            } else {
                text += " (kurs do USD: jeszcze nie pobrano)"
            }
        }
        return text
    }
}

#Preview {
    AssetsView()
        .environmentObject(PortfolioStore())
        .environmentObject(AssetColorStore())
}
