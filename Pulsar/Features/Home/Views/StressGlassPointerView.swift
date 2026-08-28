import SwiftUI

struct StressGlassPointerView: View {
    var size: CGSize
    var center: CGPoint
    var radius: CGFloat
    var bladeLength: CGFloat
    var angle: Double
    var lightSweep: Double
    var tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let orbRadius = min(15, max(12, radius * 0.145))
        let shape = StressGlassPointerShape(
            bladeLength: bladeLength,
            orbRadius: orbRadius,
            pivot: center,
            angle: angle
        )

        shape
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(reduceTransparency ? 0.98 : 0.94),
                        .white.opacity(reduceTransparency ? 0.92 : 0.72),
                        .white.opacity(reduceTransparency ? 0.96 : 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.55),
                                tint.opacity(0.05),
                                .clear
                            ],
                            center: UnitPoint(
                                x: (center.x - orbRadius * 0.28) / size.width,
                                y: (center.y - orbRadius * 0.34) / size.height
                            ),
                            startRadius: 0,
                            endRadius: orbRadius * 1.6
                        )
                    )
            }
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.95),
                                .white.opacity(0.35),
                                .black.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay {
                hubDetail(orbRadius: orbRadius)
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bladeLength * 0.30)
                .offset(x: CGFloat(lightSweep) * bladeLength * 0.72)
                .frame(width: size.width, height: size.height)
                .mask(shape)
            }
            .frame(width: size.width, height: size.height)
            .glassEffect(
                reduceTransparency ? .identity : .regular.tint(.white.opacity(0.20)),
                in: shape
            )
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .shadow(color: .black.opacity(0.05), radius: 1.2, y: 0.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Concentric watch-hub detailing so the pivot reads as a machined cap
    /// rather than a flat disc.
    private func hubDetail(orbRadius: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.05), lineWidth: 1)
                .frame(width: orbRadius * 1.28, height: orbRadius * 1.28)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.94, blue: 0.96),
                            .white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(.white.opacity(0.9), lineWidth: 0.8)
                }
                .frame(width: orbRadius * 0.62, height: orbRadius * 0.62)
                .shadow(color: .black.opacity(0.07), radius: 1, y: 0.5)
        }
        .position(center)
        .frame(width: size.width, height: size.height)
    }
}
