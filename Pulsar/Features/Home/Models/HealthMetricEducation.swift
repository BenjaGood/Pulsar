//
//  HealthMetricEducation.swift
//  Pulsar
//

import Foundation

struct HealthMetricEducation {
    struct Highlight: Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
        var detail: String
    }

    struct Factor: Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
    }

    struct Insights {
        var stable: String
        var higher: String
        var lower: String
        var unavailable: String
    }

    var subtitle: String
    var definition: String
    var highlights: [Highlight]
    var factorsTitle: String
    var factors: [Factor]
    var insights: Insights
}

extension HealthMetricKind {
    var education: HealthMetricEducation {
        switch self {
        case .respiratoryRate:
            HealthMetricEducation(
                subtitle: "Your breathing rate shows how efficiently your body is exchanging oxygen.",
                definition: "Respiratory rate (RR) is the number of breaths you take each minute. At rest, it reflects how your body is responding to sleep, recovery, activity, and everyday demands.",
                highlights: [
                    .init(symbol: "eye", title: "Early Insight", detail: "A meaningful change can be an early signal of stress, fatigue, or illness."),
                    .init(symbol: "leaf", title: "Recovery", detail: "A steady resting rate often accompanies calm, restorative recovery."),
                    .init(symbol: "figure.run", title: "Performance", detail: "Efficient breathing supports endurance, focus, and exercise readiness.")
                ],
                factorsTitle: "What affects your RR?",
                factors: [
                    .init(symbol: "bolt", title: "Stress"),
                    .init(symbol: "moon", title: "Sleep Quality"),
                    .init(symbol: "figure.walk", title: "Activity"),
                    .init(symbol: "mountain.2", title: "Altitude"),
                    .init(symbol: "cross.case", title: "Illness"),
                    .init(symbol: "wineglass", title: "Alcohol"),
                    .init(symbol: "pills", title: "Medication")
                ],
                insights: .init(
                    stable: "Your respiratory rate is close to your usual range, which can be a reassuring sign of steady recovery.",
                    higher: "A higher respiratory rate can follow stress, hard training, altitude, or illness. Consider the trend alongside how you feel.",
                    lower: "A lower respiratory rate can accompany calm recovery. Focus on the pattern over time rather than one reading.",
                    unavailable: "Wear your usual device overnight to build a more useful respiratory-rate pattern."
                )
            )

        case .restingHeartRate:
            HealthMetricEducation(
                subtitle: "Your resting pulse reflects how hard your heart works when your body is at ease.",
                definition: "Resting heart rate (RHR) is the number of times your heart beats each minute while you are relaxed. Your personal pattern can reflect recovery, fitness, stress, and overall cardiovascular load.",
                highlights: [
                    .init(symbol: "heart", title: "Cardio Load", detail: "It offers a simple view of how much work your heart is doing at rest."),
                    .init(symbol: "arrow.triangle.2.circlepath", title: "Recovery", detail: "Changes from your usual range can reflect incomplete recovery or strain."),
                    .init(symbol: "figure.run", title: "Fitness", detail: "A lower personal baseline may develop as aerobic fitness improves.")
                ],
                factorsTitle: "What affects your RHR?",
                factors: [
                    .init(symbol: "bolt", title: "Stress"),
                    .init(symbol: "moon", title: "Sleep"),
                    .init(symbol: "figure.run", title: "Training Load"),
                    .init(symbol: "drop", title: "Hydration"),
                    .init(symbol: "wineglass", title: "Alcohol"),
                    .init(symbol: "cross.case", title: "Illness"),
                    .init(symbol: "cup.and.saucer", title: "Caffeine")
                ],
                insights: .init(
                    stable: "Your resting heart rate is near your usual range, suggesting a familiar level of cardiovascular demand.",
                    higher: "A higher resting heart rate can follow poor sleep, stress, dehydration, illness, or a demanding workout.",
                    lower: "A lower resting heart rate may reflect strong recovery or improving fitness when it is typical for you.",
                    unavailable: "Consistent overnight wear helps reveal your personal resting-heart-rate pattern."
                )
            )

        case .hrv:
            HealthMetricEducation(
                subtitle: "The variation between heartbeats offers a window into recovery and nervous-system balance.",
                definition: "Heart rate variability (HRV) measures subtle differences in time between heartbeats. It is highly personal, so changes relative to your own baseline matter more than comparisons with other people.",
                highlights: [
                    .init(symbol: "waveform.path.ecg", title: "Recovery", detail: "HRV can reflect how ready your body is to adapt to another day of demand."),
                    .init(symbol: "brain.head.profile", title: "Balance", detail: "It responds to the shifting balance between stress and restoration."),
                    .init(symbol: "chart.line.uptrend.xyaxis", title: "Long View", detail: "Patterns across many nights are usually more useful than one result.")
                ],
                factorsTitle: "What affects your HRV?",
                factors: [
                    .init(symbol: "bolt", title: "Stress"),
                    .init(symbol: "moon", title: "Sleep"),
                    .init(symbol: "figure.run", title: "Training"),
                    .init(symbol: "wineglass", title: "Alcohol"),
                    .init(symbol: "drop", title: "Hydration"),
                    .init(symbol: "cross.case", title: "Illness"),
                    .init(symbol: "lungs", title: "Breathing")
                ],
                insights: .init(
                    stable: "Your HRV is close to your usual range, suggesting a familiar balance between stress and recovery.",
                    higher: "A higher-than-usual HRV often accompanies good recovery, but your longer-term pattern provides the best context.",
                    lower: "A lower HRV can follow stress, poor sleep, illness, alcohol, or hard training. A lighter day may support recovery.",
                    unavailable: "Regular overnight measurements are the best way to establish a meaningful personal HRV baseline."
                )
            )

        case .oxygenSaturation:
            HealthMetricEducation(
                subtitle: "Blood oxygen shows how much oxygen your red blood cells are carrying.",
                definition: "Blood oxygen saturation (SpO₂) estimates the percentage of hemoglobin carrying oxygen. Wearable readings are most useful for noticing patterns, not for making a diagnosis.",
                highlights: [
                    .init(symbol: "lungs", title: "Oxygen Delivery", detail: "It reflects one part of how oxygen moves from your lungs through your body."),
                    .init(symbol: "moon", title: "Overnight View", detail: "Nighttime patterns can add context to breathing and sleep quality."),
                    .init(symbol: "mountain.2", title: "Environment", detail: "Altitude and air conditions can influence your usual readings.")
                ],
                factorsTitle: "What affects your SpO₂?",
                factors: [
                    .init(symbol: "mountain.2", title: "Altitude"),
                    .init(symbol: "lungs", title: "Breathing"),
                    .init(symbol: "moon", title: "Sleep Position"),
                    .init(symbol: "cross.case", title: "Illness"),
                    .init(symbol: "hand.raised", title: "Sensor Fit"),
                    .init(symbol: "figure.walk", title: "Movement"),
                    .init(symbol: "wind", title: "Air Quality")
                ],
                insights: .init(
                    stable: "Your blood oxygen is within its familiar pattern. Look for consistency across several nights.",
                    higher: "Your blood oxygen is above its recent reference, which is usually best understood as part of the wider trend.",
                    lower: "A lower wearable reading can be affected by fit, movement, altitude, or breathing. Recheck and consider how you feel.",
                    unavailable: "A secure, comfortable sensor fit during sleep can help produce more consistent blood-oxygen readings."
                )
            )

        case .wristTemperature:
            HealthMetricEducation(
                subtitle: "Nighttime wrist temperature reveals small shifts from your personal baseline.",
                definition: "Wrist temperature tracks overnight changes at the skin relative to your own baseline. It naturally differs from a clinical body-temperature measurement and is most meaningful as a trend.",
                highlights: [
                    .init(symbol: "thermometer.medium", title: "Baseline Shift", detail: "Small deviations can reveal that your body is responding to a change."),
                    .init(symbol: "moon", title: "Recovery Context", detail: "Overnight temperature adds context to sleep and recovery signals."),
                    .init(symbol: "calendar", title: "Body Rhythms", detail: "Longer patterns may reflect environment, routines, or hormonal cycles.")
                ],
                factorsTitle: "What affects your temperature?",
                factors: [
                    .init(symbol: "cross.case", title: "Illness"),
                    .init(symbol: "bed.double", title: "Room Climate"),
                    .init(symbol: "wineglass", title: "Alcohol"),
                    .init(symbol: "figure.run", title: "Training"),
                    .init(symbol: "moon", title: "Sleep"),
                    .init(symbol: "calendar", title: "Cycle"),
                    .init(symbol: "pills", title: "Medication")
                ],
                insights: .init(
                    stable: "Your temperature trend is close to baseline, suggesting no notable overnight shift.",
                    higher: "A warmer trend can follow illness, a warm room, alcohol, hard training, or hormonal changes.",
                    lower: "A cooler trend can reflect room conditions, recovery changes, or normal variation around your baseline.",
                    unavailable: "Consistent overnight wear helps establish the personal baseline needed for temperature insights."
                )
            )

        case .sleep:
            HealthMetricEducation(
                subtitle: "Sleep duration shows how much time your body had to restore overnight.",
                definition: "Sleep duration is the total time you were estimated to be asleep. It is one part of sleep quality, alongside timing, continuity, sleep stages, and how rested you feel.",
                highlights: [
                    .init(symbol: "brain.head.profile", title: "Mind", detail: "Sleep supports attention, memory, mood, and emotional regulation."),
                    .init(symbol: "heart", title: "Recovery", detail: "Restorative sleep gives your body time to repair and rebalance."),
                    .init(symbol: "figure.run", title: "Readiness", detail: "Consistent sleep supports energy, coordination, and performance.")
                ],
                factorsTitle: "What affects your sleep?",
                factors: [
                    .init(symbol: "clock", title: "Schedule"),
                    .init(symbol: "bolt", title: "Stress"),
                    .init(symbol: "cup.and.saucer", title: "Caffeine"),
                    .init(symbol: "wineglass", title: "Alcohol"),
                    .init(symbol: "figure.run", title: "Activity"),
                    .init(symbol: "bed.double", title: "Environment"),
                    .init(symbol: "iphone", title: "Screen Time")
                ],
                insights: .init(
                    stable: "Your sleep duration is close to your usual range. A consistent schedule can help protect that rhythm.",
                    higher: "More sleep than usual can support recovery after accumulated fatigue or a demanding day.",
                    lower: "Less sleep than usual may affect energy and recovery. An earlier, consistent wind-down could help tonight.",
                    unavailable: "Wear your usual device to bed and keep a consistent schedule to build a clearer sleep pattern."
                )
            )
        }
    }
}
