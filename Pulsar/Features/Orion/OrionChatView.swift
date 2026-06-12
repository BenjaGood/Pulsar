//
//  OrionChatView.swift
//  Pulsar
//

import SwiftUI

struct OrionChatView: View {
    @ObservedObject var viewModel: OrionChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(.white.opacity(0.08))

                messageList

                inputArea
            }
            .background(chatBackground)
            .navigationBarBackButtonHidden(true)
        }
        .presentationBackground(.regularMaterial)
        .onAppear {
            isInputFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            OrionLogoView(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Orion")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Your Pulsar intelligence assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Orion")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        OrionMessageRow(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        OrionThinkingRow()
                            .id("orion-thinking")
                    }

                    if let error = viewModel.errorMessage {
                        OrionErrorRow(message: error) {
                            viewModel.clearError()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages) { _, messages in
                guard let id = messages.last?.id else { return }
                withAnimation(.smooth(duration: 0.28)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isSending) { _, isSending in
                guard isSending else { return }
                withAnimation(.smooth(duration: 0.28)) {
                    proxy.scrollTo("orion-thinking", anchor: .bottom)
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Orion...", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(viewModel.sendCurrentMessage)
                    .padding(.vertical, 11)
                    .padding(.leading, 15)

                Button(action: viewModel.sendCurrentMessage) {
                    Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .opacity(viewModel.canSend ? 1 : 0.46)
                .accessibilityLabel("Send message")
                .padding(.trailing, 8)
                .padding(.bottom, 4)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var chatBackground: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.09).opacity(0.70),
                    Color(red: 0.08, green: 0.13, blue: 0.18).opacity(0.38),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct OrionMessageRow: View {
    let message: OrionMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .user {
                Spacer(minLength: 42)
            } else {
                OrionLogoView(size: 28)
            }

            Text(message.content)
                .font(.callout)
                .foregroundStyle(message.role == .user ? Color.white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.55)
                }
                .frame(maxWidth: 290, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 42)
            }
        }
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.42, blue: 0.92),
                    Color(red: 0.18, green: 0.68, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            : AnyShapeStyle(.thinMaterial)
    }

    private var borderColor: Color {
        message.role == .user ? .white.opacity(0.16) : .white.opacity(0.12)
    }
}

private struct OrionThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            OrionLogoView(size: 28)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Orion is thinking...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer(minLength: 42)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OrionErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .layoutPriority(1)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.orange.opacity(0.24), lineWidth: 0.6)
        }
    }
}

#Preview("Orion Chat") {
    OrionChatView(viewModel: .preview)
}
