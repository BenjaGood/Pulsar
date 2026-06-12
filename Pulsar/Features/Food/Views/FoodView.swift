//
//  FoodView.swift
//  Pulsar
//

import SwiftUI

struct FoodView: View {
    @ObservedObject private var store: PulsarNutritionStore
    @State private var activeSheet: NutritionSheet?

    init(store: PulsarNutritionStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PulsarSectionBackground()
                    .ignoresSafeArea()

                ScrollView {
                    nutritionContent
                        .padding(.horizontal, 18)
                        .padding(.top, 30)
                        .padding(.bottom, 34)
                }
                .safeAreaPadding(.bottom, 16)
                .scrollContentBackground(.hidden)
                .premiumScrollHeaderBlur()
                .refreshable {
                    store.reload()
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .capture(.lunch)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add food")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                sheetView(sheet)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .background(PulsarSectionBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var nutritionContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                dailyStack
            }
        } else {
            dailyStack
        }
    }

    private var dailyStack: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            NutritionPageTitleHeader()

            if let error = store.lastPersistenceError {
                nutritionErrorCard(error)
            }

            NutritionTodayCard(
                dashboard: store.dashboard,
                onAddFood: { activeSheet = .capture(.lunch) }
            )

            NutritionQuickCaptureCard(
                meals: NutritionDailyMeal.primaryMeals,
                onQuickAdd: { activeSheet = .capture($0) }
            )

            VStack(alignment: .leading, spacing: 14) {
                ForEach(NutritionDailyMeal.primaryMeals) { meal in
                    NutritionDailyMealCard(
                        meal: meal,
                        entries: entries(for: meal),
                        onAdd: { activeSheet = .capture(meal.defaultMoment) },
                        onEdit: { entry in activeSheet = .edit(entry) },
                        onDelete: store.deleteEntry
                    )
                }
            }
        }
    }

    private func entries(for meal: NutritionDailyMeal) -> [PulsarNutritionEntry] {
        meal.moments
            .flatMap { store.entriesForToday(in: $0) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private func nutritionErrorCard(_ message: String) -> some View {
        PulsarNutritionGlassCard(cornerRadius: 22) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .capture(let moment):
            FuelCaptureSheet(store: store, initialMoment: moment)
        case .edit(let entry):
            FuelCaptureSheet(store: store, initialMoment: entry.mealMoment, editingEntry: entry)
        }
    }
}

private enum NutritionSheet: Identifiable {
    case capture(PulsarNutritionMealMoment)
    case edit(PulsarNutritionEntry)

    var id: String {
        switch self {
        case .capture(let moment): "capture-\(moment.rawValue)"
        case .edit(let entry): "edit-\(entry.id.uuidString)"
        }
    }
}

private struct NutritionDailyMeal: Identifiable {
    var title: String
    var symbolName: String
    var defaultMoment: PulsarNutritionMealMoment
    var moments: [PulsarNutritionMealMoment]
    var emptyTitle: String

    var id: String { title }
    var tint: Color { defaultMoment.tint }

    static let primaryMeals: [NutritionDailyMeal] = [
        NutritionDailyMeal(
            title: "Breakfast",
            symbolName: "sunrise.fill",
            defaultMoment: .breakfast,
            moments: [.breakfast],
            emptyTitle: "No breakfast yet"
        ),
        NutritionDailyMeal(
            title: "Lunch",
            symbolName: "sun.max.fill",
            defaultMoment: .lunch,
            moments: [.lunch],
            emptyTitle: "No lunch yet"
        ),
        NutritionDailyMeal(
            title: "Dinner",
            symbolName: "moon.stars.fill",
            defaultMoment: .dinner,
            moments: [.dinner],
            emptyTitle: "No dinner yet"
        ),
        NutritionDailyMeal(
            title: "Snacks",
            symbolName: "leaf.fill",
            defaultMoment: .snacks,
            moments: [.snacks],
            emptyTitle: "No snacks yet"
        )
    ]
}

private struct NutritionQuickCaptureCard: View {
    var meals: [NutritionDailyMeal]
    var onQuickAdd: (PulsarNutritionMealMoment) -> Void

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(
                    title: "Quick add",
                    subtitle: "Choose the meal and log what happened."
                )
                NutritionQuickAddGrid(meals: meals, onQuickAdd: onQuickAdd)
            }
        }
    }
}

private struct NutritionQuickAddGrid: View {
    var meals: [NutritionDailyMeal]
    var onQuickAdd: (PulsarNutritionMealMoment) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(meals) { meal in
                Button {
                    onQuickAdd(meal.defaultMoment)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: meal.symbolName)
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                        Text(meal.title)
                            .pulsarTextStyle(.appBodyEmphasis)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 0)
                        Image(systemName: "plus")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(meal.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(meal.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(meal.tint.opacity(0.16), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(meal.title)")
            }
        }
    }
}

private struct NutritionDailyMealCard: View {
    var meal: NutritionDailyMeal
    var entries: [PulsarNutritionEntry]
    var onAdd: () -> Void
    var onEdit: (PulsarNutritionEntry) -> Void
    var onDelete: (PulsarNutritionEntry) -> Void

    private var totals: PulsarNutritionFacts {
        entries.reduce(.zero) { $0 + $1.nutrition }
    }

    private var subtitle: String {
        guard !entries.isEmpty else { return meal.emptyTitle }
        let calories = PulsarNutritionFormatters.calories(totals.calories)
        let protein = PulsarNutritionFormatters.grams(totals.protein)
        return "\(calories) cal · \(protein) protein"
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: meal.symbolName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(meal.tint)
                        .frame(width: 38, height: 38)
                        .background(meal.tint.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.title)
                            .pulsarTextStyle(.cardTitle)
                        Text(subtitle)
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(NutritionIconButtonStyle(tint: meal.tint, size: 34))
                    .accessibilityLabel("Add \(meal.title)")
                }

                if !entries.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            NutritionDailyEntryRow(
                                entry: entry,
                                tint: meal.tint,
                                onEdit: { onEdit(entry) },
                                onDelete: { onDelete(entry) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct NutritionDailyEntryRow: View {
    var entry: PulsarNutritionEntry
    var tint: Color
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.food.name)
                            .pulsarTextStyle(.appBodyEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(entry.servingText)
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PulsarNutritionFormatters.calories(entry.nutrition.calories))
                            .pulsarMonospacedMetric(.appBodyEmphasis)
                            .foregroundStyle(.primary)
                        Text(PulsarNutritionFormatters.grams(entry.nutrition.protein))
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("More actions for \(entry.food.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

#Preview {
    FoodView(store: PulsarNutritionStore())
}
