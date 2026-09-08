//
//  PortfolioTrackerApp.swift
//  PortfolioTracker
//
//  Created by Kacper Chudzik on 08/09/2026.
//

import SwiftUI

@main
struct PortfolioTrackerApp: App {
    @StateObject private var store = PortfolioStore()
    @StateObject private var colorStore = AssetColorStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(colorStore)
        }
    }
}
