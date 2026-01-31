//
//  PayrollPeriod.swift
//  ShopBuddy
//
//  Created by Dan on 1/30/26.
//

import Foundation
import SwiftData

@Model
final class PayrollPeriod {
    var startDate: Date
    var endDate: Date
    var isProcessed: Bool
    
    // Relationship to link to the employees/hours worked
    @Relationship(deleteRule: .cascade)
    var entries: [PayrollEntry] = []

    init(startDate: Date = Date(), endDate: Date = Date().addingTimeInterval(1209600), isProcessed: Bool = false) {
        self.startDate = startDate
        self.endDate = endDate
        self.isProcessed = isProcessed
    }
}
