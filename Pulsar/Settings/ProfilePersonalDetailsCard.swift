//
//  ProfilePersonalDetailsCard.swift
//  Pulsar
//

import SwiftUI

struct ProfilePersonalDetailsCard: View {
    @Binding var name: String
    @Binding var dateOfBirth: Date
    var ageText: String
    @Binding var biologicalSex: BiologicalSex

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isNameFocused: Bool
    @State private var isEditingDateOfBirth = false
    @State private var isShowingAgeInformation = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsIcon(symbol: "person.fill", tint: .black, size: 40)
                        headerText
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsIcon(symbol: "person.fill", tint: .black, size: 40)
                        headerText
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ProfileDetailRow(
                    symbol: "person",
                    tint: .black,
                    label: "Name"
                ) {
                    TextField("Name", text: $name, prompt: Text("Not set"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                } action: {
                    Button(
                        "Edit Name",
                        systemImage: "pencil",
                        action: focusName
                    )
                    .profileActionControl(controlSize: .regular)
                }

                divider

                ProfileDetailRow(
                    symbol: "calendar",
                    tint: .black,
                    label: "Date of Birth"
                ) {
                    Text(
                        dateOfBirth,
                        format: .dateTime.day().month(.abbreviated).year()
                    )
                    .font(.headline)
                    .foregroundStyle(.primary)
                } action: {
                    Button(
                        "Edit Date of Birth",
                        systemImage: "calendar",
                        action: showDateOfBirthEditor
                    )
                    .profileActionControl(controlSize: .regular)
                    .popover(isPresented: $isEditingDateOfBirth) {
                        DatePicker(
                            "Date of Birth",
                            selection: $dateOfBirth,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        .presentationCompactAdaptation(.sheet)
                    }
                }

                divider

                ProfileDetailRow(
                    symbol: "clock",
                    tint: .black,
                    label: "Derived Age",
                    subtitle: "Calculated from date of birth"
                ) {
                    Text(ageText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                } action: {
                    Button(
                        "About Derived Age",
                        systemImage: "info.circle",
                        action: showAgeInformation
                    )
                    .profileActionControl(controlSize: .regular)
                }

                divider

                ProfileDetailRow(
                    symbol: "figure.dress.line.vertical.figure",
                    tint: .black,
                    label: "Biological Sex"
                ) {
                    Text(biologicalSex.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                } action: {
                    Menu(
                        "Change Biological Sex",
                        systemImage: "chevron.up.chevron.down"
                    ) {
                        Picker("Biological Sex", selection: $biologicalSex) {
                            ForEach(BiologicalSex.allCases) { sex in
                                Text(sex.rawValue).tag(sex)
                            }
                        }
                    }
                    .profileActionControl(controlSize: .regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .pulsarSettingsCardSurface(cornerRadius: 26)
        .alert(
            "Derived Age",
            isPresented: $isShowingAgeInformation
        ) {
        } message: {
            Text("Pulsar calculates age from the selected date of birth.")
        }
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 52)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Personal Details")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Personalizes your Pulsar experience.")
                .font(dynamicTypeSize.isAccessibilitySize ? .subheadline : .footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func focusName() {
        isNameFocused = true
    }

    private func showDateOfBirthEditor() {
        isEditingDateOfBirth = true
    }

    private func showAgeInformation() {
        isShowingAgeInformation = true
    }
}
