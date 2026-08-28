//
//  ProfileSettingsDetailViews.swift
//  Pulsar
//

import PhotosUI
import SwiftUI

struct ProfileDetailsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoErrorMessage = ""
    @State private var isShowingPhotoError = false
    private let calendar = Calendar.current

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        ScrollView {
            PulsarGlassEffectGroup(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileHeader()

                    ProfileAvatarSection(
                        profile: draft,
                        selectedPhotoItem: $selectedPhotoItem
                    )

                    ProfilePersonalDetailsCard(
                        name: $draft.name,
                        dateOfBirth: dateOfBirthBinding,
                        ageText: ageText,
                        biologicalSex: $draft.biologicalSex
                    )

                    ProfileInfoFooterCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(PulsarSettingsBackground())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: dismissProfile)
                    .profileActionControl(tint: .primary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Text("Save")
                        .bold()
                        .foregroundStyle(
                            hasChanges
                                ? SettingsMonochromeDesign.primary
                                : SettingsMonochromeDesign.disabled
                        )
                        .animation(.easeInOut(duration: 0.2), value: hasChanges)
                }
                .buttonStyle(SettingsOutlineButtonStyle())
                .disabled(!hasChanges)
            }
        }
        .task(id: selectedPhotoItem) {
            await loadSelectedPhoto()
        }
        .alert(
            "Unable to Load Photo",
            isPresented: $isShowingPhotoError
        ) {
        } message: {
            Text(photoErrorMessage)
        }
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }

    private var hasChanges: Bool { draft != store.profile }

    private var dateOfBirthBinding: Binding<Date> {
        Binding(get: { draft.dateOfBirth ?? draft.healthKitDateOfBirth ?? defaultDateOfBirth }, set: { draft.dateOfBirth = $0 })
    }

    private var defaultDateOfBirth: Date {
        calendar.date(byAdding: .year, value: -30, to: .now) ?? .now
    }

    private var ageText: String {
        guard let age = draft.age(calendar: calendar) else { return "Not set" }
        return "\(age) years"
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        onSave?()
    }

    private func dismissProfile() {
        dismiss()
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }

        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil else {
                presentPhotoError("The selected image could not be read. Please choose another photo.")
                return
            }

            draft.photoData = data
        } catch {
            presentPhotoError("The selected photo could not be loaded. Check its availability and try again.")
        }
    }

    private func presentPhotoError(_ message: String) {
        photoErrorMessage = message
        isShowingPhotoError = true
    }
}

struct SettingsDetailScaffold<Content: View>: View {
    var title: String
    var hasChanges: Bool
    var save: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
        }
        .background(PulsarSettingsBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
    }
}

#Preview("Profile Details") { NavigationStack { ProfileDetailsView(store: SettingsPreviewStore.make()) } }
