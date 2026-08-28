import SwiftUI

struct PremiumStrainGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var current: Int?
    var targetRange: PulsarSharedStrainTargetRange?

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                let geometry = StrainGaugeGeometry(
                    width: proxy.size.width,
                    targetRange: targetRange
                )

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.055))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

                    if let targetRange {
                        Capsule()
                            .fill(StrainDetailsDesign.strainOrange.opacity(0.12))
                            .frame(
                                width: max(
                                    6,
                                    geometry.position(for: targetRange.upperBound)
                                        - geometry.position(for: targetRange.lowerBound)
                                )
                            )
                            .offset(x: geometry.position(for: targetRange.lowerBound))
                    }

                    if let current {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.78, blue: 0.34),
                                        StrainDetailsDesign.strainOrange,
                                        StrainDetailsDesign.strainRed
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geometry.position(for: current)))
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(.white.opacity(0.34))
                                    .frame(height: 2)
                            }
                    }

                    if let targetRange {
                        StrainGaugeBoundary(
                            position: geometry.position(for: targetRange.lowerBound)
                        )
                        StrainGaugeBoundary(
                            position: geometry.position(for: targetRange.upperBound),
                            color: .white.opacity(0.94),
                            width: 3,
                            height: 20
                        )
                    }
                }
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.65),
                    value: current
                )
            }
            .frame(height: 16)

            GeometryReader { proxy in
                let geometry = StrainGaugeGeometry(
                    width: proxy.size.width,
                    targetRange: targetRange
                )

                Text("0")
                    .position(x: 6, y: 9)

                Text(targetRange.map { "\($0.lowerBound)" } ?? "—")
                    .position(
                        x: targetRange.map {
                            geometry.labelPosition(for: $0.lowerBound)
                        } ?? geometry.width * 0.34,
                        y: 9
                    )

                Text(targetRange.map { "\($0.upperBound)" } ?? "—")
                    .position(
                        x: targetRange.map {
                            geometry.labelPosition(for: $0.upperBound)
                        } ?? geometry.width * 0.66,
                        y: 9
                    )

                Text("20+")
                    .position(x: max(geometry.width - 13, 13), y: 9)
            }
            .frame(height: 19)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strain gauge")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let currentText = current.map(String.init) ?? "unavailable"
        let targetText = targetRange?.displayText ?? "unavailable"
        return "Current strain \(currentText), target range \(targetText)"
    }
}
