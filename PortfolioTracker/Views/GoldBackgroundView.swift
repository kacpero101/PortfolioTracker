//
//  GoldBackgroundView.swift
//  PortfolioTracker
//
//  Delikatne błękitne tło okna z bardzo jasnym wykresem ceny złota (USD/oz) od 1975 roku.
//  Tło jest wyłącznie dekoracyjne: nie przyjmuje kliknięć, jest pomijane przez VoiceOver
//  i ma niski kontrast, żeby nie konkurować z treścią zakładek.
//

import SwiftUI
import Charts

struct GoldBackgroundView: View {
    @StateObject private var model = GoldPriceHistoryModel()
    @Environment(\.colorScheme) private var colorScheme

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.07, green: 0.10, blue: 0.16), Color(red: 0.05, green: 0.08, blue: 0.13)]
            : [Color(red: 0.91, green: 0.95, blue: 1.00), Color(red: 0.96, green: 0.98, blue: 1.00)]
    }

    private var goldColor: Color {
        Color(red: 0.80, green: 0.62, blue: 0.16)
    }

    private var decadeTicks: [Date] {
        stride(from: 1980, through: 2020, by: 10).map { GoldPriceHistory.midYear($0) }
    }

    private var maxPrice: Double {
        model.points.map(\.price).max() ?? 1
    }

    private var yearRange: String {
        guard let first = model.points.first?.date, let last = model.points.last?.date else { return "" }
        let calendar = Calendar(identifier: .gregorian)
        return "\(calendar.component(.year, from: first))–\(calendar.component(.year, from: last))"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)

            Chart(model.points) { point in
                AreaMark(
                    x: .value("Data", point.date),
                    y: .value("Cena", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [goldColor.opacity(0.14), goldColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Data", point.date),
                    y: .value("Cena", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(goldColor.opacity(colorScheme == .dark ? 0.35 : 0.30))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            // Zapas u góry, żeby szczyt wykresu nie wchodził pod nagłówki zakładek.
            .chartYScale(domain: 0...(maxPrice * 1.6))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: decadeTicks) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(String(Calendar(identifier: .gregorian).component(.year, from: date)))
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.45))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Text("Złoto, USD/oz · \(yearRange)")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.55))
                .padding(.trailing, 28)
                .padding(.bottom, 34)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await model.refreshIfNeeded() }
    }
}

#Preview {
    GoldBackgroundView()
        .frame(width: 900, height: 600)
}
