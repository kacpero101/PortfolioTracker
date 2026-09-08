//
//  AllocationChartView.swift
//  PortfolioTracker
//
//  Wykres kołowy pokazujący procentową alokację portfela
//  między klasami aktywów (akcje, ETF-y, obligacje, gotówka, krypto).
//
//  Wymaga frameworka Swift Charts (macOS 13+ / Xcode 14+).
//

import SwiftUI
import Charts

struct AllocationChartView: View {
    let entries: [PortfolioStore.AllocationEntry]
    @EnvironmentObject private var colorStore: AssetColorStore

    /// Typ, dla którego aktualnie otwarty jest picker koloru.
    @State private var editingType: AssetType? = nil

    var body: some View {
        HStack(spacing: 24) {
            Chart(entries) { entry in
                SectorMark(
                    angle: .value("Wartość", entry.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(colorStore.color(for: entry.type))
                .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .frame(maxWidth: .infinity)

            // Własna legenda — kółko koloru jest klikalne i otwiera picker.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    HStack {
                        Button {
                            editingType = editingType == entry.type ? nil : entry.type
                        } label: {
                            Circle()
                                .fill(colorStore.color(for: entry.type))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Zmień kolor")
                        .popover(isPresented: Binding(
                            get: { editingType == entry.type },
                            set: { if !$0 { editingType = nil } }
                        )) {
                            ColorPickerPopover(type: entry.type)
                                .environmentObject(colorStore)
                        }

                        Text(entry.type.rawValue)
                        Spacer()
                        Text(String(format: "%.1f%%", entry.percent))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .frame(width: 180)
        }
    }
}

// MARK: - Popover z siatką 16 kolorów

private struct ColorPickerPopover: View {
    let type: AssetType
    @EnvironmentObject private var colorStore: AssetColorStore

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kolor: \(type.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<AssetColorStore.palette.count, id: \.self) { index in
                    let selected = colorStore.colorIndex(for: type) == index
                    Circle()
                        .fill(AssetColorStore.palette[index])
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().stroke(
                            selected ? Color.primary : Color.clear,
                            lineWidth: 1.5
                        ))
                        .onTapGesture {
                            colorStore.setColor(index: index, for: type)
                        }
                }
            }
        }
        .padding(12)
    }
}

#Preview {
    AllocationChartView(entries: [
        .init(type: .stock, value: 6000, percent: 60),
        .init(type: .etf, value: 3000, percent: 30),
        .init(type: .cash, value: 1000, percent: 10)
    ])
    .frame(height: 260)
    .padding()
    .environmentObject(AssetColorStore())
}
