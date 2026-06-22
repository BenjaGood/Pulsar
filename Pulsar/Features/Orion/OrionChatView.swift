//
//  OrionChatView.swift
//  Pulsar
//

import SwiftUI

struct OrionChatView: View {
    @ObservedObject var viewModel: OrionChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool
    @State private var isSceneVisible = false
    @State private var isHistoryPresented = false

    var body: some View {
        ZStack {
            OrionConversationBackdrop()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

            conversationSurface
                .opacity(isSceneVisible ? 1 : 0)
                .scaleEffect(reduceMotion || isSceneVisible ? 1 : 0.992, anchor: .center)

            if isHistoryPresented {
                OrionChatHistoryView(
                    viewModel: viewModel,
                    isPresented: $isHistoryPresented
                )
                .transition(historyTransition)
                .zIndex(4)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .onAppear {
            let animation = reduceMotion ? Animation.easeOut(duration: 0.12) : .smooth(duration: 0.38)
            withAnimation(animation) {
                isSceneVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isInputFocused = true
            }
        }
    }

    private var conversationSurface: some View {
        VStack(spacing: 0) {
            topControls
            messageList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputArea
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            OrionIconButton(systemName: "clock.arrow.circlepath") {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(historyAnimation) {
                    isHistoryPresented = true
                    isInputFocused = false
                }
            }
            .accessibilityLabel("Open Orion history")

            OrionIconButton(systemName: "xmark") {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                dismiss()
            }
            .accessibilityLabel("Close Orion")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(viewModel.messages) { message in
                        OrionMessageBlock(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        OrionWorkingRow()
                            .id("orion-working")
                    }

                    if let error = viewModel.errorMessage {
                        OrionErrorRow(message: error) {
                            viewModel.clearError()
                        }
                    }
                }
                .padding(.horizontal, horizontalMessagePadding)
                .padding(.top, 54)
                .padding(.bottom, 178)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .onChange(of: viewModel.messages) { _, messages in
                guard let id = messages.last?.id else { return }
                scrollTo(id, proxy: proxy)
            }
            .onChange(of: viewModel.isSending) { _, isSending in
                guard isSending else { return }
                scrollTo("orion-working", proxy: proxy)
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Orion", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(viewModel.sendCurrentMessage)
                    .padding(.vertical, 13)
                    .padding(.leading, 18)
                    .layoutPriority(1)

                Button(action: viewModel.sendCurrentMessage) {
                    Image(systemName: viewModel.isSending ? "sparkle.magnifyingglass" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(viewModel.canSend ? 0.96 : 0.46))
                        .frame(width: 35, height: 35)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
                .padding(.trailing, 8)
                .padding(.bottom, 7)
            }
            .frame(maxWidth: 620)
            .background(OrionFloatingGlassBackground(cornerRadius: 27))
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 10)
        }
    }

    private var historyTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .bottom))
        )
    }

    private var historyAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.42)
    }

    private var horizontalMessagePadding: CGFloat {
        24
    }

    private func scrollTo<ID: Hashable>(_ id: ID, proxy: ScrollViewProxy) {
        let animation = reduceMotion ? Animation.easeOut(duration: 0.12) : .smooth(duration: 0.28)
        withAnimation(animation) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func dismissKeyboard() {
        guard isInputFocused else { return }
        isInputFocused = false
    }
}

private struct OrionConversationBackdrop: View {
    var body: some View {
        ZStack {
            Color.clear

            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.70),
                            .init(color: .black.opacity(0.50), location: 0.84),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Color.black
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.76),
                            .init(color: .black.opacity(0.88), location: 0.84),
                            .init(color: .black.opacity(0.34), location: 0.92),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private struct OrionMessageBlock: View {
    let message: OrionMessage

    var body: some View {
        switch message.role {
        case .assistant, .system:
            assistantText
        case .user:
            userText
        }
    }

    private var assistantText: some View {
        Text(message.content)
            .font(.system(size: 26, weight: .regular))
            .lineSpacing(3.5)
            .foregroundStyle(.white.opacity(0.92))
            .textSelection(.enabled)
            .frame(maxWidth: 560, alignment: .leading)
            .accessibilityLabel("Orion: \(message.content)")
    }

    private var userText: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.34),
                            Color(red: 0.68, green: 0.80, blue: 1.0).opacity(0.18),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .frame(maxHeight: 58)
                .padding(.top, 5)

            Text(message.content)
                .font(.system(size: 24, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.76))
                .textSelection(.enabled)
                .frame(maxWidth: 540, alignment: .leading)
                .accessibilityLabel("You: \(message.content)")
        }
        .padding(.leading, 20)
        .frame(maxWidth: 590, alignment: .leading)
    }
}

private struct OrionWorkingRow: View {
    var body: some View {
        HStack(spacing: 13) {
            OrionWorkingGlyph(size: 30)

            Text("Working…")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Orion is working")
    }
}

private struct OrionWorkingGlyph: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: dotSize(for: index), height: dotSize(for: index))
                    .shadow(color: Color(red: 0.58, green: 0.74, blue: 1.0).opacity(0.78), radius: 4, x: 0, y: 0)
                    .opacity(opacity(for: index))
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(Double(index) * 36))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.08 : 0.94))
        .opacity(reduceMotion ? 1 : (isAnimating ? 1 : 0.72))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.18).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        guard !reduceMotion else { return 0.86 }
        let emphasizedIndex = isAnimating ? 1 : 6
        let distance = abs(index - emphasizedIndex)
        return distance <= 1 ? 1.0 : 0.34 + Double(index % 3) * 0.11
    }

    private func dotSize(for index: Int) -> CGFloat {
        size * (index.isMultiple(of: 3) ? 0.16 : 0.13)
    }
}

private struct OrionErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.86))
                .layoutPriority(1)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(13)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.orange.opacity(0.26), lineWidth: 0.8)
        }
    }
}

private struct OrionChatHistoryView: View {
    @ObservedObject var viewModel: OrionChatViewModel
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var isSearchActive = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            OrionHistoryAmbientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if isSearchActive {
                        searchField
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    historyGrid
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            historyActions
        }
        .onChange(of: isSearchActive) { _, isActive in
            guard isActive else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isSearchFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Orion")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))

                Text("History")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
            }

            Spacer(minLength: 12)

            OrionIconButton(systemName: "xmark") {
                close()
            }
            .accessibilityLabel("Close Orion history")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.64))

            TextField("Search Orion chats", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .focused($isSearchFocused)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(OrionFloatingGlassBackground(cornerRadius: 24, tint: Color(red: 0.58, green: 0.72, blue: 1.0)))
    }

    @ViewBuilder
    private var historyGrid: some View {
        let conversations = viewModel.conversations(matching: searchText)
        if conversations.isEmpty {
            OrionHistoryEmptyState(isSearching: isSearchActive && !searchText.isEmpty)
                .frame(maxWidth: .infinity)
        } else {
            historyCardGrid(conversations)
        }
    }

    @ViewBuilder
    private func historyCardGrid(_ conversations: [OrionConversation]) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                historyCardGridContent(conversations)
            }
        } else {
            historyCardGridContent(conversations)
        }
    }

    private func historyCardGridContent(_ conversations: [OrionConversation]) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 148, maximum: 260), spacing: 14, alignment: .top)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                Button {
                    viewModel.selectConversation(conversation)
                    close()
                } label: {
                    OrionHistoryCard(
                        conversation: conversation,
                        index: index,
                        isOffset: index % 2 == 1
                    )
                }
                .buttonStyle(.plain)
                .offset(y: index % 2 == 1 ? 28 : 0)
                .padding(.bottom, index % 2 == 1 ? 28 : 0)
                .accessibilityLabel("\(conversation.displayTitle). \(conversation.previewText)")
            }
        }
    }

    private var historyActions: some View {
        HStack {
            OrionRoundActionButton(
                systemName: "magnifyingglass",
                isSelected: isSearchActive
            ) {
                withAnimation(historyAnimation) {
                    isSearchActive.toggle()
                    if !isSearchActive {
                        searchText = ""
                        isSearchFocused = false
                    }
                }
            }
            .accessibilityLabel(isSearchActive ? "Hide search" : "Search Orion history")

            Spacer()

            OrionRoundActionButton(systemName: "square.and.pencil") {
                viewModel.startNewConversation()
                close()
            }
            .accessibilityLabel("Start new Orion chat")
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background {
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.72),
                    .black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var historyAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.34)
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(historyAnimation) {
            isPresented = false
        }
    }
}

private struct OrionHistoryCard: View {
    let conversation: OrionConversation
    let index: Int
    let isOffset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(Self.startTimeText(for: conversation))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                thumbnail
            }

            Text(conversation.displayTitle)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .minimumScaleFactor(0.84)

            Text(conversation.previewText)
                .font(.system(size: 13, weight: .semibold))
                .lineSpacing(1.5)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(isOffset ? 5 : 4)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .modifier(OrionHistoryCardGlassSurface(cornerRadius: 28, tint: tint))
        .overlay(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    tint.opacity(0.12),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 18)
            .padding(.bottom, 1)
        }
    }

    private var thumbnail: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))

            if let symbol = conversation.thumbnailSystemName {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            } else {
                OrionLogoView(size: 24)
            }
        }
        .frame(width: 34, height: 34)
    }

    private var titleSize: CGFloat {
        index.isMultiple(of: 3) ? 22 : 20
    }

    private var minHeight: CGFloat {
        switch index % 4 {
        case 0: 186
        case 1: 154
        case 2: 176
        default: 164
        }
    }

    private var tint: Color {
        switch index % 5 {
        case 0: Color(red: 0.58, green: 0.70, blue: 1.0)
        case 1: Color(red: 0.64, green: 0.92, blue: 0.86)
        case 2: Color(red: 0.96, green: 0.78, blue: 0.54)
        case 3: Color(red: 0.86, green: 0.66, blue: 1.0)
        default: Color(red: 0.62, green: 0.82, blue: 1.0)
        }
    }

    private static func startTimeText(for conversation: OrionConversation) -> String {
        let date = conversation.startedAt
        let time = timeText(for: date)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(time)"
        }
        return dateTimeText(for: date)
    }

    private static func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func dateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        return formatter.string(from: date)
    }
}

private struct OrionHistoryCardGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(Color.black.opacity(0.24), in: shape)
                .background(darkSurface, in: shape)
                .glassEffect(
                    .regular.tint(Color.black.opacity(0.24)).interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    border(for: shape, primaryOpacity: 0.24, secondaryOpacity: 0.08)
                }
                .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 14)
                .shadow(color: tint.opacity(0.045), radius: 18, x: 0, y: 5)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(darkSurface, in: shape)
                .overlay {
                    border(for: shape, primaryOpacity: 0.18, secondaryOpacity: 0.06)
                }
                .shadow(color: .black.opacity(0.20), radius: 20, x: 0, y: 12)
        }
    }

    private var darkSurface: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.030),
                tint.opacity(0.045),
                Color(red: 0.018, green: 0.024, blue: 0.038).opacity(0.40),
                Color.black.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func border(
        for shape: RoundedRectangle,
        primaryOpacity: Double,
        secondaryOpacity: Double
    ) -> some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(primaryOpacity),
                        tint.opacity(secondaryOpacity),
                        .white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.65
            )
            .blendMode(.plusLighter)
    }
}

private struct OrionHistoryEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            OrionLogoView(size: 48)
                .opacity(0.84)

            Text(isSearching ? "No matching chats" : "No Orion chats yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))

            Text(isSearching ? "Try a different title, summary, or message preview." : "Start a conversation and it will appear here.")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.52))
                .frame(maxWidth: 260)
        }
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
    }
}

private struct OrionHistoryAmbientBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.22, green: 0.28, blue: 0.46).opacity(0.20),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 340
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.24, blue: 0.34).opacity(0.24),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 300
            )
        }
    }
}

private struct OrionIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 40, height: 40)
                .background(
                    OrionFloatingGlassBackground(
                        cornerRadius: 20,
                        tint: Color(red: 0.60, green: 0.70, blue: 1.0),
                        opacity: 0.52
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OrionRoundActionButton: View {
    let systemName: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 56, height: 56)
                .background(
                    OrionFloatingGlassBackground(
                        cornerRadius: 28,
                        tint: isSelected ? Color(red: 0.78, green: 0.88, blue: 1.0) : Color(red: 0.60, green: 0.70, blue: 1.0),
                        opacity: isSelected ? 0.86 : 0.62
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OrionFloatingGlassBackground: View {
    var cornerRadius: CGFloat
    var tint: Color = .white
    var opacity: Double = 0.76
    var darkening: Double = 0.14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .clear.interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            ZStack {
                shape
                    .fill(.ultraThinMaterial)

                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.34 * opacity),
                                .white.opacity(0.16 * opacity),
                                .white.opacity(0.08 * opacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.16 * opacity), radius: 18, x: 0, y: 10)
        }
    }
}

#Preview("Orion Chat") {
    OrionChatView(viewModel: .preview)
        .background(StaticTimeBackgroundView(mode: .night))
}

#Preview("Orion History") {
    OrionChatHistoryView(
        viewModel: .preview,
        isPresented: .constant(true)
    )
}
