//
//  PulsarScrollAwareInlineTitle.swift
//  Pulsar
//

import SwiftUI

private struct PulsarScrollAwareInlineTitleModifier: ViewModifier {
    var title: String
    var largeTitleHeight: CGFloat

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let offset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                return PulsarCollapsingHeaderProgress.value(
                    scrollOffset: offset,
                    expandedHeaderHeight: largeTitleHeight
                )
            } action: { _, newProgress in
                if progress != newProgress {
                    progress = newProgress
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .pulsarTextStyle(.sectionHeader)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(Double(progress))
                        .offset(y: reduceMotion ? 0 : (1 - progress) * 4)
                        .accessibilityHidden(progress <= 0.05)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .modifier(PulsarScrollEdgeTopEffectModifier())
    }
}

extension View {
    func pulsarScrollAwareInlineTitle(
        _ title: String,
        largeTitleHeight: CGFloat = 56
    ) -> some View {
        modifier(
            PulsarScrollAwareInlineTitleModifier(
                title: title,
                largeTitleHeight: largeTitleHeight
            )
        )
    }
}
