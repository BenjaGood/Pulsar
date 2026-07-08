//
//  PulsarScreenScaffold.swift
//  Pulsar
//

import SwiftUI

struct PulsarScreenHeaderBlur {
    var height: CGFloat = 56
    var fadeStart: CGFloat = 8
    var fadeEnd: CGFloat = 40

    static let standard = PulsarScreenHeaderBlur()
}

struct PulsarScreenScaffold<Background: View, Content: View>: View {
    @ObservedObject var layoutStore: PulsarBottomChromeLayoutStore

    private let horizontalPadding: CGFloat
    private let topPadding: CGFloat?
    private let spacing: CGFloat
    private let headerBlur: PulsarScreenHeaderBlur?
    private let reservesBottomChrome: Bool
    private let onRefresh: (() async -> Void)?
    private let onScrollOffsetChange: ((CGFloat) -> Void)?
    private let background: Background
    private let content: Content

    init(
        layoutStore: PulsarBottomChromeLayoutStore,
        horizontalPadding: CGFloat = 22,
        topPadding: CGFloat? = nil,
        spacing: CGFloat = 14,
        headerBlur: PulsarScreenHeaderBlur? = nil,
        reservesBottomChrome: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        onScrollOffsetChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content
    ) {
        self.layoutStore = layoutStore
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.spacing = spacing
        self.headerBlur = headerBlur
        self.reservesBottomChrome = reservesBottomChrome
        self.onRefresh = onRefresh
        self.onScrollOffsetChange = onScrollOffsetChange
        self.background = background()
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedTopPadding = topPadding ?? Self.topChromeClearance(for: proxy.safeAreaInsets.top)

            ZStack {
                background
                    .ignoresSafeArea()

                configuredScroll(
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: spacing) {
                            content
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, resolvedTopPadding)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .pulsarBottomChromeScrollContainerIfNeeded(
                        layoutStore: layoutStore,
                        reservesBottomChrome: reservesBottomChrome
                    )
                    .scrollContentBackground(.hidden)
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    @ViewBuilder
    private func configuredScroll<ScrollContent: View>(_ scroll: ScrollContent) -> some View {
        let offsetAwareScroll = applyScrollOffsetReporting(scroll)
        let blurredScroll = applyHeaderBlur(offsetAwareScroll)
        applyRefresh(blurredScroll)
    }

    @ViewBuilder
    private func applyScrollOffsetReporting<ScrollContent: View>(_ scroll: ScrollContent) -> some View {
        if let onScrollOffsetChange {
            scroll
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    onScrollOffsetChange(offset)
                }
        } else {
            scroll
        }
    }

    @ViewBuilder
    private func applyHeaderBlur<ScrollContent: View>(_ scroll: ScrollContent) -> some View {
        if let headerBlur {
            scroll
                .premiumScrollHeaderBlur(
                    height: headerBlur.height,
                    fadeStart: headerBlur.fadeStart,
                    fadeEnd: headerBlur.fadeEnd
                )
        } else {
            scroll
        }
    }

    @ViewBuilder
    private func applyRefresh<ScrollContent: View>(_ scroll: ScrollContent) -> some View {
        if let onRefresh {
            scroll
                .refreshable {
                    await onRefresh()
                }
        } else {
            scroll
        }
    }

    private static func topChromeClearance(for safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop > 0 ? 16 : 64
    }
}

private extension View {
    @ViewBuilder
    func pulsarBottomChromeScrollContainerIfNeeded(
        layoutStore: PulsarBottomChromeLayoutStore,
        reservesBottomChrome: Bool
    ) -> some View {
        if reservesBottomChrome {
            pulsarBottomChromeScrollContainer(layoutStore: layoutStore)
        } else {
            scrollBounceBehavior(.basedOnSize)
        }
    }
}
