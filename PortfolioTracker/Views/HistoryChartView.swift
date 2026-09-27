//
//  HistoryChartView.swift
//  PortfolioTracker
//
//  Wykres liniowy pokazujący jak zmieniała się wartość
//  całego portfela w czasie (jeden punkt na dzień odświeżenia).
//

import SwiftUI
import Charts

struct HistoryChartView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Wartość portfela w czasie")
                    .font(.largeTitle.bold())
                Spacer()
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("Wyczyść historię", systemImage: "trash")
                }
                .disabled(store.history.isEmpty)
                .confirmationDialog(
                    "Wyczyścić historię wartości portfela?",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("Wyczyść", role: .destructive) {
                        store.clearHistory()
                    }
                    Button("Anuluj", role: .cancel) {}
                } message: {
                    Text("Zostanie usuniętych \(store.history.count) punktów historii. Wykres zacznie się od nowa od bieżącej wartości portfela (\(store.totalValue.formatted(.currency(code: "USD")))). Tej operacji nie można cofnąć.")
                }
            }
            .padding(.top)

            if store.history.count < 2 {
                ContentUnavailableView(
                    "Za mało danych",
                    systemImage: "chart.xyaxis.line",
                    description: Text(
                        "Historia zapisuje się automatycznie przy każdym odświeżeniu cen i każdej zmianie pozycji (jeden punkt dziennie). Wróć tu po kilku dniach korzystania z aplikacji."
                    )
                )
            } else {
                Chart(store.history) { snapshot in
                    LineMark(
                        x: .value("Data", snapshot.date),
                        y: .value("Wartość", snapshot.totalValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Data", snapshot.date),
                        y: .value("Wartość", snapshot.totalValue)
                    )
                    .foregroundStyle(.blue)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if let doubleValue = value.as(Double.self) {
                            AxisValueLabel(doubleValue.formatted(.currency(code: "USD")))
                        }
                    }
                }
                .frame(minHeight: 300)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    HistoryChartView()
        .environmentObject(PortfolioStore())
}
