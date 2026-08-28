import SwiftUI

struct ProductCustomServingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let units: [ProductServingUnit]
    let save: (Double, ProductServingUnit) -> Bool

    @State private var amount = 1.0
    @State private var selectedUnit: ProductServingUnit
    @State private var showsValidationError = false

    init(units: [ProductServingUnit], save: @escaping (Double, ProductServingUnit) -> Bool) {
        self.units = units
        self.save = save
        _selectedUnit = State(initialValue: units.first ?? .gram)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom serving")
                        .font(.title3.weight(.semibold))
                    Text("Only supported conversions are available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close custom serving")
            }

            HStack(spacing: 12) {
                TextField("Amount", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.title3.monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .pulsarLiquidGlass(cornerRadius: 16, interactive: true, isClear: true)
                    .accessibilityLabel("Custom serving amount")

                Picker("Unit", selection: $selectedUnit) {
                    ForEach(units) { unit in
                        Text(unit.shortName).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.glass)
                .frame(minWidth: 100, minHeight: 50)
            }

            if showsValidationError {
                Label("This amount cannot be calculated reliably for this product.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button("Use custom serving", systemImage: "checkmark") {
                if save(amount, selectedUnit) {
                    dismiss()
                } else {
                    showsValidationError = true
                }
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity)
            .disabled(!amount.isFinite || amount <= 0)
        }
        .padding(20)
        .presentationDetents([.height(showsValidationError ? 300 : 250)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
}
