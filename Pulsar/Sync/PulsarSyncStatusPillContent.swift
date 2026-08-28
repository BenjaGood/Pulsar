import SwiftUI

struct PulsarSyncStatusPillContent: View {
    let state: PulsarSyncBannerCenter.State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .syncing(let message):
                pill(message: message, mood: .syncing)
                    .transition(statusTransition)
            case .success(let message):
                pill(message: message, mood: .success)
                    .transition(statusTransition)
            case .failure(let message):
                pill(message: message, mood: .failure)
                    .transition(statusTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.smooth(duration: 0.28), value: state)
    }

    @ViewBuilder
    private func pill(message: String, mood: Mood) -> some View {
        let content = HStack(spacing: 10) {
            Group {
                if mood == .syncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.secondary)
                } else {
                    Image(systemName: mood.symbol)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(mood.symbolColor)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            Text(message)
                .pulsarTextStyle(.metadata)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(mood.accessibilityValue)

        Group {
            if reduceTransparency {
                content
                    .background(Color(.systemBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.primary.opacity(0.12), lineWidth: 0.75)
                    }
            } else if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .capsule)
            } else {
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.18), lineWidth: 0.75)
                    }
            }
        }
        .id(mood)
    }

    private var statusTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }
}

private extension PulsarSyncStatusPillContent {
    enum Mood: Hashable {
        case syncing
        case success
        case failure

        var symbolColor: Color {
            switch self {
            case .syncing: .secondary
            case .success: .green
            case .failure: .orange
            }
        }

        var symbol: String {
            switch self {
            case .syncing: "arrow.triangle.2.circlepath"
            case .success: "checkmark"
            case .failure: "exclamationmark"
            }
        }

        var accessibilityValue: LocalizedStringKey {
            switch self {
            case .syncing: "In progress"
            case .success: "Completed"
            case .failure: "Failed"
            }
        }
    }
}

#Preview("Syncing") {
    PulsarSyncStatusPillContent(state: .syncing("Syncing health data…"))
        .padding(32)
        .background(Color(.systemGroupedBackground))
}

#Preview("Synced") {
    PulsarSyncStatusPillContent(state: .success("Health data synced"))
        .padding(32)
        .background(Color(.systemGroupedBackground))
}
