import SwiftUI

struct PulsarSyncStatusPill: View {
    @ObservedObject var center: PulsarSyncBannerCenter = .shared
    @State private var shimmerOffset = -180.0
    @State private var pulse = false

    var body: some View {
        Group {
            switch center.state {
            case .hidden:
                EmptyView()
            case .syncing(let message):
                pill(message: message, mood: .syncing)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            case .success(let message):
                pill(message: message, mood: .success)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            case .failure(let message):
                pill(message: message, mood: .failure)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.smooth(duration: 0.28), value: center.state)
    }

    private func pill(message: String, mood: SyncPillMood) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(mood.tint.opacity(0.14))
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse && mood == .syncing ? 1.08 : 1)
                if mood == .syncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(mood.tint)
                } else {
                    Image(systemName: mood.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mood.tint)
                        .scaleEffect(pulse && mood == .success ? 1.08 : 1)
                }
            }

            Text(message)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [mood.tint.opacity(0.13), Color.white.opacity(0.06), mood.tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.36), mood.tint.opacity(0.30), Color.white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            if mood == .syncing {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.32), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 110)
                    .offset(x: shimmerOffset)
                    .blendMode(.screen)
            }
        }
        .clipShape(Capsule(style: .continuous))
        .pulsarLiquidGlass(cornerRadius: 24)
        .shadow(color: mood.tint.opacity(0.16), radius: 18, y: 9)
        .id(mood)
        .onAppear {
            shimmerOffset = -180
            pulse = false
            if mood == .syncing {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmerOffset = 180
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else if mood == .success {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) {
                    pulse = true
                }
            }
        }
        .onDisappear {
            shimmerOffset = -180
            pulse = false
        }
    }
}

private enum SyncPillMood: Hashable {
    case syncing
    case success
    case failure

    var tint: Color {
        switch self {
        case .syncing: .cyan
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
}
