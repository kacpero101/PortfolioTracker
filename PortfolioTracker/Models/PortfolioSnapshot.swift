//
//  PortfolioSnapshot.swift
//  PortfolioTracker
//
//  Pojedynczy punkt na wykresie wartości portfela w czasie.
//  Zapisujemy jeden snapshot dziennie (przy każdym odświeżeniu cen).
//

import Foundation

struct PortfolioSnapshot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var totalValue: Double
}
