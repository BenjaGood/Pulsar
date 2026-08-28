import SwiftUI

struct GymSavedRoutinesHeader: View {
    var onBack: () -> Void
    var onCreateRoutine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                GymRoutineGlassIconButton(
                    title: "Back",
                    systemImage: "chevron.left",
                    action: onBack
                )

                Spacer(minLength: 20)

                GymRoutineGlassIconButton(
                    title: "Create routine",
                    systemImage: "plus",
                    action: onCreateRoutine
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("My Routines")
                    .pulsarTextStyle(.screenTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                Text("Saved lifting plans, ready when you are.")
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct GymRoutineGlassIconButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
                .background(
                    PulsarCircularGlassSurface(
                        cornerRadius: 24,
                        tint: .white,
                        opacity: 0.72
                    )
                )
        }
        .buttonStyle(GymRoutinePressButtonStyle())
        .accessibilityLabel(title)
    }
}

struct GymRoutinePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}
