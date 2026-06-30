//
//  DailyJournalCheckInSheet.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct DailyJournalCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PulsarDailyJournalDraft

    var onSave: (PulsarDailyJournalDraft) -> Void

    init(
        draft: PulsarDailyJournalDraft,
        onSave: @escaping (PulsarDailyJournalDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily check-in")
                            .pulsarTextStyle(.displayLarge)
                        Text(draft.prompt ?? "Let the day be simple.")
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    PulsarMindfulnessGlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            MindfulnessSignalSlider(
                                title: "Overall mood",
                                lowLabel: "Heavy",
                                highLabel: "Bright",
                                systemImage: "heart.text.square.fill",
                                tint: moodTint,
                                value: $draft.valence,
                                range: -1...1
                            )

                            VStack(spacing: 14) {
                                MindfulnessSignalSlider(title: "Energy", lowLabel: "Low", highLabel: "High", systemImage: "bolt.fill", tint: .orange, value: $draft.energy)
                                MindfulnessSignalSlider(title: "Stress", lowLabel: "Soft", highLabel: "Loaded", systemImage: "waveform.path.ecg", tint: .pink, value: $draft.stress)
                                MindfulnessSignalSlider(title: "Gratitude", lowLabel: "Quiet", highLabel: "Present", systemImage: "sparkles", tint: .green, value: $draft.gratitude)
                                MindfulnessSignalSlider(title: "Anxiety", lowLabel: "Low", highLabel: "High", systemImage: "wind", tint: .purple, value: $draft.anxiety)
                                MindfulnessSignalSlider(title: "Social", lowLabel: "Alone", highLabel: "Connected", systemImage: "person.2.fill", tint: .teal, value: $draft.socialConnection)
                                MindfulnessSignalSlider(title: "Productivity", lowLabel: "Loose", highLabel: "Clear", systemImage: "checkmark.circle.fill", tint: .blue, value: $draft.productivity)
                                MindfulnessSignalSlider(title: "Sleep", lowLabel: "Poor", highLabel: "Rested", systemImage: "moon.zzz.fill", tint: .indigo, value: $draft.sleepPerception)
                            }
                        }
                    }

                    PulsarMindfulnessGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Emotions")
                                .pulsarTextStyle(.cardTitle)
                            TagFlowLayout(spacing: 8) {
                                ForEach(PulsarJournalEmotionLabel.allCases) { label in
                                    MindfulnessChip(
                                        title: label.title,
                                        systemImage: label.symbolName,
                                        isSelected: draft.emotionLabels.contains(label),
                                        tint: moodTint
                                    ) {
                                        toggle(label)
                                    }
                                }
                            }
                        }
                    }

                    PulsarMindfulnessGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Contributing signals")
                                .pulsarTextStyle(.cardTitle)
                            TagFlowLayout(spacing: 8) {
                                ForEach(PulsarJournalAssociation.allCases) { association in
                                    MindfulnessChip(
                                        title: association.title,
                                        systemImage: association.symbolName,
                                        isSelected: draft.associations.contains(association),
                                        tint: .blue
                                    ) {
                                        toggle(association)
                                    }
                                }
                            }
                        }
                    }

                    PulsarMindfulnessGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Reflection")
                                    .pulsarTextStyle(.cardTitle)
                                Spacer()
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Image(systemName: "mic.fill")
                                        .pulsarTextStyle(.label)
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .secondary))
                                .accessibilityLabel("Voice note")
                            }

                            TextEditor(text: $draft.note)
                                .pulsarTextStyle(.body)
                                .frame(minHeight: 96)
                                .scrollContentBackground(.hidden)
                                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(PulsarSectionBackground())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text("Save")
                            .fontWeight(.bold)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var moodTint: Color {
        if draft.valence > 0.22 { return .green }
        if draft.valence < -0.22 { return .orange }
        return .blue
    }

    private func toggle(_ label: PulsarJournalEmotionLabel) {
        UISelectionFeedbackGenerator().selectionChanged()
        if draft.emotionLabels.contains(label) {
            draft.emotionLabels.remove(label)
        } else {
            draft.emotionLabels.insert(label)
        }
    }

    private func toggle(_ association: PulsarJournalAssociation) {
        UISelectionFeedbackGenerator().selectionChanged()
        if draft.associations.contains(association) {
            draft.associations.remove(association)
        } else {
            draft.associations.insert(association)
        }
    }
}

private struct MindfulnessSignalSlider: View {
    var title: String
    var lowLabel: String
    var highLabel: String
    var systemImage: String
    var tint: Color
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.13), in: Circle())
                Text(title)
                    .pulsarTextStyle(.label)
                Spacer()
                Text(scoreText)
                    .pulsarTextStyle(.captionEmphasis)
                                .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
                .tint(tint)

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .pulsarTextStyle(.overline)
            .foregroundStyle(.secondary)
        }
    }

    private var scoreText: String {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return "\(Int((normalized * 100).rounded()))"
    }
}

private struct MindfulnessChip: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(isSelected ? tint.opacity(0.86) : Color.white.opacity(0.08), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.18) : tint.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TagFlowLayout<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            content
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > width, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [FlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(index: index, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct FlowItem {
        var index: Int
        var size: CGSize
    }

    private struct FlowRow {
        var items: [FlowItem]
        var height: CGFloat
    }
}
