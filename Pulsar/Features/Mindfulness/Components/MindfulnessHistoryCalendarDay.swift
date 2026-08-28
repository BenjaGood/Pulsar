//
//  MindfulnessHistoryCalendarDay.swift
//  Pulsar
//

import Foundation

struct MindfulnessHistoryCalendarDay: Identifiable {
    var date: Date
    var isInDisplayedMonth: Bool

    var id: Date { date }
}
