//
//  PulsarScreenScaffold.swift
//  Pulsar
//

import SwiftUI

enum PulsarTabLayout {
    static let horizontalPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 14
    static let primaryCardCornerRadius: CGFloat = 30
    static let primaryCardShadowOpacity = 0.055
    static let primaryCardShadowRadius: CGFloat = 22
    static let primaryCardShadowY: CGFloat = 12
}

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
    private let headerConfiguration: PulsarScreenHeaderConfiguration?
    private let expandedHeaderContent: AnyView?
    private let reservesBottomChrome: Bool
    private let onRefresh: (() async -> Void)?
    private let background: Background
    private let content: Content

    @State private var expandedHeaderHeight: CGFloat = 0
    @State private var collapsingHeaderProgressModel = PulsarCollapsingHeaderProgressModel()

    init(
        layoutStore: PulsarBottomChromeLayoutStore,
        horizontalPadding: CGFloat = PulsarTabLayout.horizontalPadding,
        topPadding: CGFloat? = nil,
        spacing: CGFloat = PulsarTabLayout.sectionSpacing,
        headerBlur: PulsarScreenHeaderBlur? = nil,
        reservesBottomChrome: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content
    ) {
        self.layoutStore = layoutStore
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.spacing = spacing
        self.headerBlur = headerBlur
        self.headerConfiguration = nil
        self.expandedHeaderContent = nil
        self.reservesBottomChrome = reservesBottomChrome
        self.onRefresh = onRefresh
        self.background = background()
        self.content = content()
    }

    init<ExpandedHeader: View>(
        layoutStore: PulsarBottomChromeLayoutStore,
        header: PulsarScreenHeaderConfiguration,
        horizontalPadding: CGFloat = PulsarTabLayout.horizontalPadding,
        topPadding: CGFloat? = nil,
        spacing: CGFloat = PulsarTabLayout.sectionSpacing,
        reservesBottomChrome: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder background: () -> Background,
        @ViewBuilder expandedHeader: () -> ExpandedHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.layoutStore = layoutStore
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.spacing = spacing
        self.headerBlur = nil
        self.headerConfiguration = header
        self.expandedHeaderContent = AnyView(expandedHeader())
        self.reservesBottomChrome = reservesBottomChrome
        self.onRefresh = onRefresh
        self.background = background()
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedTopPadding = topPadding ?? Self.topChromeClearance(for: proxy.safeAreaInsets.top)

            ZStack(alignment: .top) {
                background
                    .ignoresSafeArea()

                configuredScroll(
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: spacing) {
                            expandedHeaderSection
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

                if let headerConfiguration {
                    PulsarCollapsingHeaderBarHost(
                        configuration: headerConfiguration,
                        safeAreaTop: proxy.safeAreaInsets.top,
                        progressModel: collapsingHeaderProgressModel
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var expandedHeaderSection: some View {
        if let expandedHeaderContent {
            expandedHeaderContent
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { _, height in
                    guard abs(expandedHeaderHeight - height) > 0.5 else { return }
                    expandedHeaderHeight = height
                }
        }
    }

    @ViewBuilder
    private func configuredScroll<ScrollContent: View>(_ scroll: ScrollContent) -> some View {
        let headerAwareScroll = applyCollapsingHeaderProgress(scroll)
        let blurredScroll = applyHeaderBlur(headerAwareScroll)
        applyRefresh(blurredScroll)
    }

    @ViewBuilder
    private func applyCollapsingHeaderProgress<ScrollContent: View>(
        _ scroll: ScrollContent
    ) -> some View {
        if headerConfiguration != nil {
            scroll
                .pulsarCollapsingHeaderProgress(
                    expandedHeaderHeight: expandedHeaderHeight,
                    progressModel: collapsingHeaderProgressModel
                )
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
