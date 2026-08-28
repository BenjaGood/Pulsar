//
//  LabBiomarkersOverview.swift
//  Pulsar
//

import SwiftUI

struct LabBiomarkersSection: View {
    let biomarkers: [LabBiomarker]
    let onImport: () -> Void
    let onManualEntry: () -> Void
    let onDelete: (LabBiomarker) -> Void

    @State private var selectedBiomarker: LabBiomarker?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabBiomarkersHeader(
                onImport: onImport,
                onManualEntry: onManualEntry
            )

            LazyVStack(spacing: 10) {
                ForEach(biomarkers, id: \.labOverviewIdentity) { biomarker in
                    Button {
                        select(biomarker)
                    } label: {
                        LabBiomarkerOverviewRow(biomarker: biomarker)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 10)
        .sheet(item: $selectedBiomarker) { biomarker in
            BiomarkerDetailView(biomarker: biomarker, onDelete: {
                selectedBiomarker = nil
                onDelete(biomarker)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func select(_ biomarker: LabBiomarker) {
        selectedBiomarker = biomarker
    }
}

private struct LabBiomarkersHeader: View {
    let onImport: () -> Void
    let onManualEntry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                LabBiomarkersTitle()

                LabBiomarkerActions(
                    onImport: onImport,
                    onManualEntry: onManualEntry
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 10) {
                    LabBiomarkersTitle()
                        .frame(maxWidth: 160, alignment: .leading)

                    Spacer(minLength: 0)

                    LabBiomarkerActions(
                        onImport: onImport,
                        onManualEntry: onManualEntry
                    )
                    .frame(width: 170)
                }

                VStack(alignment: .leading, spacing: 14) {
                    LabBiomarkersTitle()

                    LabBiomarkerActions(
                        onImport: onImport,
                        onManualEntry: onManualEntry
                    )
                    .frame(width: 170)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct LabBiomarkersTitle: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Biomarkers")
                .font(.title2.weight(.semibold))
                .foregroundStyle(PulsarTabPalette.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Professional lab records used by the biological age engine.")
                .font(.caption.scaled(by: 0.94))
                .foregroundStyle(PulsarTabPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LabBiomarkerActions: View {
    let onImport: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LabBiomarkerActionButton(
                title: "Import PDF",
                symbol: "doc.badge.plus",
                action: onImport
            )
            LabBiomarkerActionButton(
                title: "Enter manually",
                symbol: "square.and.pencil",
                action: onManualEntry
            )
        }
    }
}

private struct LabBiomarkerActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.scaled(by: 0.86))
                    .foregroundStyle(PulsarTabPalette.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PulsarTabPalette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 70)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .labReferenceGlassSurface(
            cornerRadius: 22,
            isInteractive: true,
            shadowOpacity: 0.016,
            shadowRadius: 8,
            shadowY: 3,
            fillOpacity: 0.32
        )
        .accessibilityLabel(title)
    }
}

private struct LabBiomarkerOverviewRow: View {
    let biomarker: LabBiomarker

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: LabBiomarkerRowPresentation {
        LabBiomarkerRowPresentation(biomarker: biomarker)
    }

    @ViewBuilder
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        LabBiomarkerIcon()
                        LabBiomarkerIdentity(presentation: presentation)
                        Spacer(minLength: 4)
                        LabBiomarkerChevron()
                    }

                    LabBiomarkerMeasurement(presentation: presentation)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    LabBiomarkerIcon()
                    LabBiomarkerIdentity(presentation: presentation)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    LabBiomarkerMeasurement(presentation: presentation)
                    LabBiomarkerChevron()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .labReferenceGlassSurface(
            cornerRadius: 26,
            isInteractive: true,
            shadowOpacity: 0.018,
            shadowRadius: 9,
            shadowY: 3,
            fillOpacity: 0.42
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.32),
            value: presentation.transitionKey
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(biomarker.name)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint("Opens biomarker details")
    }
}

private struct LabBiomarkerIcon: View {
    var body: some View {
        Image(systemName: "drop")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(PulsarTabPalette.primaryText.opacity(0.82))
            .frame(width: 44, height: 44)
            .labReferenceGlassSurface(
                cornerRadius: 22,
                shadowOpacity: 0.006,
                shadowRadius: 4,
                shadowY: 1,
                fillOpacity: 0.22
            )
            .accessibilityHidden(true)
    }
}

private struct LabBiomarkerIdentity: View {
    let presentation: LabBiomarkerRowPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(presentation.biomarker.name)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(PulsarTabPalette.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.76)

                if presentation.isMissing {
                    Text("Missing")
                        .font(.caption.scaled(by: 0.78))
                        .foregroundStyle(PulsarTabPalette.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PulsarTabPalette.separator.opacity(0.55), in: Capsule())
                        .transition(.opacity)
                }
            }

            Text(presentation.metadataText)
                .font(.caption.scaled(by: 0.88))
                .foregroundStyle(PulsarTabPalette.secondaryText)
                .contentTransition(.opacity)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
        }
    }
}

private struct LabBiomarkerMeasurement: View {
    let presentation: LabBiomarkerRowPresentation

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(presentation.valueText)
                .font(.headline.weight(.medium).monospacedDigit())
                .foregroundStyle(PulsarTabPalette.primaryText)
                .contentTransition(.numericText(value: presentation.numericTransitionValue))
                .lineLimit(1)

            Text(presentation.unitText)
                .font(.caption)
                .foregroundStyle(PulsarTabPalette.secondaryText)
                .lineLimit(1)
        }
    }
}

private struct LabBiomarkerChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(PulsarTabPalette.tertiaryText)
            .accessibilityHidden(true)
    }
}

struct LabBiomarkerRowPresentation: Equatable {
    let biomarker: LabBiomarker

    var isMissing: Bool {
        guard let value = biomarker.value else { return true }
        return !value.isFinite
    }

    var valueText: String {
        isMissing ? "--" : biomarker.displayValue
    }

    var unitText: String {
        biomarker.unit.isEmpty ? " " : biomarker.unit
    }

    var dateText: String {
        biomarker.collectedAt?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "No collection date"
    }

    var referenceText: String {
        guard let low = biomarker.referenceLow, let high = biomarker.referenceHigh else {
            return "Reference unavailable"
        }
        return "\(low.formattedLabValue) – \(high.formattedLabValue) \(biomarker.unit)"
    }

    var metadataText: String {
        "\(referenceText)  |  \(dateText)"
    }

    var numericTransitionValue: Double {
        isMissing ? 0 : biomarker.value ?? 0
    }

    var transitionKey: String {
        "\(isMissing)-\(valueText)-\(dateText)"
    }

    var accessibilityValue: String {
        if isMissing {
            return "Missing. \(dateText). Reference range \(referenceText)."
        }
        return "\(valueText) \(unitText). Collected \(dateText). Reference range \(referenceText)."
    }
}

private extension LabBiomarker {
    var labOverviewIdentity: String {
        if let definition = LabBiomarkerDefinition.definition(for: name) {
            return "required-\(definition.id)"
        }
        return "custom-\(id.uuidString)"
    }
}

#Preview("Lab Confidence and Biomarkers") {
    ScrollView {
        VStack(spacing: 24) {
            LabReferenceDataConfidenceCard(
                result: labBiomarkersPreviewResult,
                startsSettled: true
            )

            LabBiomarkersSection(
                biomarkers: labBiomarkersPreviewRows,
                onImport: {},
                onManualEntry: {},
                onDelete: { _ in }
            )
        }
        .padding(20)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}

private var labBiomarkersPreviewRows: [LabBiomarker] {
    LabBiomarkerDefinition.required.map { definition in
        let isAvailable = definition.name == "Albumin"
        return LabBiomarker(
            name: definition.name,
            value: isAvailable ? 4.2 : nil,
            unit: definition.unit,
            referenceLow: definition.referenceLow,
            referenceHigh: definition.referenceHigh,
            status: isAvailable ? definition.status(for: 4.2) : .missing,
            collectedAt: isAvailable ? Date(timeIntervalSince1970: 1_787_004_000) : nil,
            source: isAvailable ? .manual : .other,
            notes: definition.explanation
        )
    }
}

private var labBiomarkersPreviewResult: BiologicalAgeResult {
    let now = Date(timeIntervalSince1970: 1_787_004_000)
    return BiologicalAgeResult(
        biologicalAge: 23.9,
        chronologicalAge: 24,
        ageDelta: -0.1,
        paceOfAging: 0.99,
        confidence: .low,
        updatedAt: now,
        nextUpdateAt: now.addingTimeInterval(7 * 24 * 60 * 60),
        physiologicalScore: 90,
        lifestyleScore: nil,
        biomarkerScore: nil,
        physiologicalContributionYears: -0.1,
        lifestyleContributionYears: 0,
        biomarkerContributionYears: 0,
        missingDataMessages: [],
        wearableDataDays: 12,
        recentBiomarkerCount: 0,
        lifestyleSurveyCompleted: false
    )
}
