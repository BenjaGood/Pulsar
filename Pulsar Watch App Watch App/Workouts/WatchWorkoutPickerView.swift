//
//  WatchWorkoutPickerView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

private enum WatchWorkoutSection {
    case personalized
    case general
}

private struct WatchWorkoutOption: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let symbolName: String
    let tint: Color
    let section: WatchWorkoutSection
    let outdoorWorkoutKind: PulsarOutdoorWorkoutKind?
    let isGym: Bool

    var isPersonalized: Bool { section == .personalized }
}

private extension WatchWorkoutOption {
    @MainActor
    static let personalized: [WatchWorkoutOption] = PulsarWorkoutCatalog.personalizedEntries.map(Self.init(catalogEntry:))

    @MainActor
    static let general: [WatchWorkoutOption] = PulsarWorkoutCatalog.moreWorkoutEntries.map(Self.init(catalogEntry:))

    @MainActor
    init(catalogEntry entry: PulsarWorkoutCatalogEntry) {
        self.init(
            id: entry.id,
            name: entry.displayName,
            category: entry.category,
            symbolName: entry.symbolName,
            tint: Color(red: entry.tint.red, green: entry.tint.green, blue: entry.tint.blue),
            section: entry.section == .personalized ? .personalized : .general,
            outdoorWorkoutKind: entry.outdoorWorkoutKind,
            isGym: entry.isGym
        )
    }
}

struct WatchWorkoutFloatingAddButton: View {
    var action: () -> Void

    @State private var glow = false

    var body: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.green.opacity(0.20),
                                    Color.cyan.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.58), .white.opacity(0.16), .green.opacity(0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: .green.opacity(glow ? 0.34 : 0.18), radius: glow ? 15 : 9, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open workout picker")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

struct WatchWorkoutPickerView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                pickerBackdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        workoutSection(title: "Personalized Trainings", workouts: WatchWorkoutOption.personalized, isFeatured: true)
                        workoutSection(title: "More Workouts", workouts: WatchWorkoutOption.general, isFeatured: false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("")
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var pickerBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                    Color.green.opacity(0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 130
            )
            RadialGradient(
                colors: [Color.green.opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 4,
                endRadius: 150
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Choose training")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
            Text("Add a workout or jump into Run or Walk.")
                .pulsarTextStyle(.overline)
                .foregroundStyle(.white.opacity(0.60))
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private func workoutSection(title: String, workouts: [WatchWorkoutOption], isFeatured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(isFeatured ? .white.opacity(0.78) : .white.opacity(0.52))
                .padding(.horizontal, 2)

            LazyVStack(spacing: 7) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    NavigationLink {
                        destination(for: workout)
                    } label: {
                        WatchWorkoutOptionCard(workout: workout, isFeatured: isFeatured)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        WKInterfaceDevice.current().play(workout.outdoorWorkoutKind != nil ? .start : .click)
                    })
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82).delay(Double(index) * 0.025), value: appeared)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for workout: WatchWorkoutOption) -> some View {
        if let outdoorWorkoutKind = workout.outdoorWorkoutKind {
            WatchRunEntryView(workoutKind: outdoorWorkoutKind)
                .environmentObject(runManager)
        } else if workout.isGym {
            WatchGymEntryView(syncStore: .shared)
        } else {
            WatchWorkoutPlaceholderView(workout: workout)
        }
    }
}

private struct WatchWorkoutOptionCard: View {
    let workout: WatchWorkoutOption
    let isFeatured: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(workout.tint.opacity(isFeatured ? 0.24 : 0.16))
                Image(systemName: workout.symbolName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(workout.tint)
            }
            .frame(width: isFeatured ? 38 : 34, height: isFeatured ? 38 : 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(workout.name)
                    .font(.system(size: isFeatured ? 15 : 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(workout.category)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: workout.outdoorWorkoutKind != nil ? "bolt.heart.fill" : "chevron.right")
                .pulsarTextStyle(.overline)
                .foregroundStyle(workout.outdoorWorkoutKind != nil ? workout.tint : .white.opacity(0.36))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isFeatured ? 10 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: isFeatured ? 20 : 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: isFeatured ? 20 : 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            workout.tint.opacity(isFeatured ? 0.24 : 0.14),
                            Color.white.opacity(isFeatured ? 0.08 : 0.05),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: isFeatured ? 20 : 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(isFeatured ? 0.22 : 0.14), workout.tint.opacity(0.22), .black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: workout.tint.opacity(isFeatured ? 0.18 : 0.10), radius: isFeatured ? 8 : 5, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: isFeatured ? 20 : 18, style: .continuous))
        .accessibilityLabel("\(workout.name), \(workout.category)")
    }
}

private struct WatchWorkoutPlaceholderView: View {
    let workout: WatchWorkoutOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    workout.tint.opacity(0.22),
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 62, height: 62)
                    Image(systemName: workout.symbolName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(workout.tint)
                }
                .shadow(color: workout.tint.opacity(0.24), radius: 14)

                VStack(spacing: 3) {
                    Text(workout.name)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Workout mode")
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Text("Dedicated recording for this workout is coming soon. Running and Walking are ready today.")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Back") {
                    WKInterfaceDevice.current().play(.click)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(workout.tint)
            }
            .padding(.horizontal, 10)
        }
    }
}

#Preview {
    WatchWorkoutPickerView()
        .environmentObject(WatchRunSessionManager.shared)
}
