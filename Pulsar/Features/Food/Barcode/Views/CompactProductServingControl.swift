import SwiftUI

struct CompactProductServingControl: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: ProductServingModel
    @State private var customDraft: ProductCustomServingDraft?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                    compactStackedLayout
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.30), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(color: .blue.opacity(0.05), radius: 14, y: 6)
        .pulsarLiquidGlass(cornerRadius: 22)
        .sheet(item: $customDraft) { _ in
            ProductCustomServingSheet(units: model.customUnits) { amount, unit in
                model.selectCustom(amount: amount, unit: unit)
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            Text("Serving")
                .font(.headline)
                .foregroundStyle(PackagedProductStyle.ink)
                .fixedSize()
            quantityControl
            servingMenu
            Spacer(minLength: 0)
            equivalentLabel
        }
    }

    private var compactStackedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Serving")
                    .font(.headline)
                Spacer()
                equivalentLabel
            }
            HStack(spacing: 10) {
                quantityControl
                servingMenu
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Serving")
                    .font(.headline)
                Spacer(minLength: 12)
                equivalentLabel
            }
            quantityControl
            servingMenu
        }
    }

    private var quantityControl: some View {
        PulsarGlassEffectGroup(spacing: 4) {
            HStack(spacing: 0) {
                Button("Decrease quantity", systemImage: "minus") {
                    model.decrement()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass(.clear))
                .frame(width: 44, height: 44)
                .disabled(!model.canDecrement)

                Text(model.quantityText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 88 : 38)
                    .layoutPriority(1)
                    .accessibilityLabel("Quantity")
                    .accessibilityValue(model.quantityText)

                Button("Increase quantity", systemImage: "plus") {
                    model.increment()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass(.clear))
                .frame(width: 44, height: 44)
            }
        }
        .background(.white.opacity(0.22), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var servingMenu: some View {
        Menu {
            ForEach(model.options) { option in
                Button {
                    model.select(option)
                } label: {
                    if option.id == model.selectedOption.id {
                        Label(menuLabel(for: option), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(for: option))
                    }
                }
            }
            Divider()
            Button("Custom…", systemImage: "slider.horizontal.3") {
                customDraft = ProductCustomServingDraft()
            }
        } label: {
            HStack(spacing: 7) {
                Text(model.selectedTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
        }
        .buttonStyle(.glass(.clear))
        .accessibilityLabel("Serving unit")
        .accessibilityValue(model.selectedTitle)
    }

    private var equivalentLabel: some View {
        Text(model.equivalentText)
            .font(.footnote.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Equivalent amount")
            .accessibilityValue(model.equivalentText)
    }

    private func menuLabel(for option: ProductServingOption) -> String {
        if let detail = option.detail {
            return "\(option.title) — \(detail)"
        }
        return option.title
    }
}

#Preview("Compact bread serving") {
    let product = FoodProduct(
        name: "Bimbo Cero Cero",
        brand: "Bimbo",
        serving: FoodServing(quantity: 2, unit: "slice", gramWeight: 55),
        source: .openNutrition,
        verificationStatus: .imported,
        nutrients: [
            FoodNutrient(key: .energyKcal, amount: 218, unit: "kcal", basis: .per100Grams),
            FoodNutrient(key: .protein, amount: 10.9, unit: "g", basis: .per100Grams),
            FoodNutrient(key: .carbohydrates, amount: 45.45, unit: "g", basis: .per100Grams),
            FoodNutrient(key: .fat, amount: 1.82, unit: "g", basis: .per100Grams)
        ]
    )
    CompactProductServingControl(model: ProductServingModel(product: product)!)
        .padding(24)
        .background(Color.blue.opacity(0.08))
}
