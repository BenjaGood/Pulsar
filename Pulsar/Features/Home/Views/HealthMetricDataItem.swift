//
//  HealthMetricDataItem.swift
//  Pulsar
//

import Foundation

struct HealthMetricDataItem: Identifiable {
    var id: String { label }
    var symbol: String
    var label: String
    var value: String
}
