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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wartość portfela w czasie")
                .font(.largeTitle.bold())
                .padding(.top)

            if store.history.count < 2 {
                ContentUnavailableView(
                    "Za mało danych",
                    systemImage: "chart.xyaxis.line",
                    description: Text(
                        "Historia zapisuje się automatycznie przy każdym odświeżeniu cen (raz dziennie). Wróć tu po kilku dniach korzystania z aplikacji."
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
