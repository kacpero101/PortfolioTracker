//
//  SummaryView.swift
//  PortfolioTracker
//
//  Ekran podsumowania: całkowita wartość portfela, zysk/strata
//  oraz wykres kołowy alokacji między klasami aktywów.
//

import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                header

                HStack(spacing: 20) {
                    summaryCard(
                        title: "Wartość portfela",
                        value: format(store.totalValue),
                        color: .primary
                    )
                    summaryCard(
                        title: "Zysk / strata",
                        value: "\(format(store.totalProfitLoss)) (\(formatPercent(store.totalProfitLossPercent)))",
                        color: store.totalProfitLoss >= 0 ? .green : .red
                    )
                }

                if !store.allocation.isEmpty {
                    Text("Alokacja aktywów")
                        .font(.headline)
                    AllocationChartView(entries: store.allocation)
                        .frame(height: 260)
                } else {
                    ContentUnavailableView(
                        "Brak aktywów",
                        systemImage: "tray",
                        description: Text("Dodaj pierwszą pozycję w zakładce „Aktywa”, aby zobaczyć podsumowanie.")
                    )
                    .frame(height: 200)
                }

                if !store.lastRefreshErrors.isEmpty {
                    errorsBox
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Mój portfel")
                    .font(.largeTitle.bold())
                if let date = store.lastRefreshDate {
                    Text("Ostatnie odświeżenie: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refreshPrices() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Odśwież ceny", systemImage: "arrow.clockwise")
                }
            }
            .disabled(store.isRefreshing)
        }
    }

    private var errorsBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Nie udało się pobrać niektórych cen", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.bold())
            ForEach(store.lastRefreshErrors, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func format(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }
}

#Preview {
    SummaryView()
        .environmentObject(PortfolioStore())
}
