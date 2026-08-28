import SwiftUI

struct SleepGoalDaysCard: View {
    @Binding var selection: SleepGoalDays

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SLEEP GOAL DAYS")
                .sleepSectionLabel()

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 3) {
                        options
                    }
                } else {
                    HStack(spacing: 0) {
                        options
                    }
                }
            }
            .padding(3)
            .background(segmentBackground, in: RoundedRectangle(cornerRadius: 22))

            Text("Custom day selection is coming soon.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(SleepPreferencesDesign.cardPadding)
        .sleepPreferencesCardSurface()
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: selection
        )
    }

    @ViewBuilder
    private var options: some View {
        option(.everyDay)
        option(.weekdays)
        option(.custom, isDisabled: true, badge: "Soon")
    }

    private var segmentBackground: Color {
        SettingsMonochromeDesign.subtleFill
    }

    private func option(
        _ option: SleepGoalDays,
        isDisabled: Bool = false,
        badge: String? = nil
    ) -> some View {
        Button {
            selection = option
        } label: {
            VStack(spacing: 3) {
                Text(option.rawValue)
                    .font(.subheadline)
                    .bold()

                if let badge {
                    Text(badge)
                        .font(.caption)
                }
            }
            .foregroundStyle(selection == option ? Color.white : (isDisabled ? Color.secondary : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                if selection == option {
                    RoundedRectangle(cornerRadius: 19)
                        .fill(SleepPreferencesDesign.selectedGradient)
                        .matchedGeometryEffect(id: "sleep-goal-selection", in: selectionNamespace)
                        .shadow(color: SettingsMonochromeDesign.shadow, radius: 8, y: 3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityValue(selection == option ? "Selected" : (isDisabled ? "Coming soon" : ""))
    }
}

#Preview("Sleep Goal Days") {
    @Previewable @State var selection: SleepGoalDays = .everyDay

    SleepGoalDaysCard(selection: $selection)
        .padding()
        .background(PulsarSettingsBackground())
}
