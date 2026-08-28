import SwiftUI

struct MealScannerStartButton: View {
    var isStarting: Bool
    var action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            startButton
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.black)
        } else {
            startButton
                .buttonStyle(.plain)
                .background(.black, in: .capsule)
        }
    }

    private var startButton: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .semibold))
                }

                Text(isStarting ? "Preparing Camera" : "Start Scan")
                    .pulsarTextStyle(.buttonTitle)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(.capsule)
        }
        .disabled(isStarting)
        .accessibilityHint("Opens the camera and begins the two-phase meal scan")
    }
}
