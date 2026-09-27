//
//  AssetsView.swift
//  PortfolioTracker
//
//  Lista wszystkich pozycji w portfelu z możliwością dodawania,
//  edycji (tap) i usuwania (swipe / przycisk).
//

import SwiftUI

struct AssetsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var isShowingAddSheet = false
    @State private var editingAsset: Asset?

    var body: some View {
        VStack {
            if store.assets.isEmpty {
                ContentUnavailableView(
                    "Brak aktywów",
                    systemImage: "tray",
                    description: Text("Dodaj pierwszą pozycję przyciskiem „+” powyżej.")
                )
            } else {
                List {
                    ForEach(store.assets) { asset in
                        AssetRow(asset: asset)
                            .contentShape(Rectangle())
                            .onTapGesture { editingAsset = asset }
                    }
                    .onDelete { offsets in
                        store.deleteAssets(at: offsets)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Label("Dodaj aktywo", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddAssetView(assetToEdit: nil)
        }
        .sheet(item: $editingAsset) { asset in
            AddAssetView(assetToEdit: asset)
        }
    }
}

/// Pojedynczy wiersz na liście aktywów.
private struct AssetRow: View {
    let asset: Asset
    @EnvironmentObject private var colorStore: AssetColorStore

    var body: some View {
        HStack {
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
                }
                Text("\(asset.type.rawValue) · ilość: \(asset.quantity, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let series = asset.bondSeries {
                    Text(bondRateDescription(series: series))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(asset.currentValue.formatted(.currency(code: "USD")))
                    .font(.headline)
                if asset.type != .cash {
                    Text(String(format: "%+.2f%%", asset.profitLossPercent))
                        .font(.caption)
                        .foregroundStyle(asset.profitLoss >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Np. "EDO0936 · oprocentowanie 5.35% · marża 2.00%".
    private func bondRateDescription(series: String) -> String {
        var parts = [series]
        if let rate = asset.currentBondRate {
            parts.append(String(format: "oprocentowanie %.2f%%", rate))
        } else {
            parts.append("oprocentowanie: brak danych")
        }
        if let margin = asset.bondMargin {
            parts.append(String(format: "marża %.2f%%", margin))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    AssetsView()
        .environmentObject(PortfolioStore())
}
