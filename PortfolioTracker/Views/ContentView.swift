//
//  ContentView.swift
//  PortfolioTracker
//
//  Główny widok aplikacji - zakładki: Podsumowanie, Aktywa, Historia.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        TabView {
            SummaryView()
                .tabItem {
                    Label("Podsumowanie", systemImage: "chart.pie.fill")
                }

            AssetsView()
                .tabItem {
                    Label("Aktywa", systemImage: "list.bullet")
                }

            HistoryChartView()
                .tabItem {
                    Label("Historia", systemImage: "chart.xyaxis.line")
                }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(PortfolioStore())
}
