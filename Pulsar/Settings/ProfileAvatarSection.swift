//
//  ProfileAvatarSection.swift
//  Pulsar
//

import PhotosUI
import SwiftUI

struct ProfileAvatarSection: View {
    var profile: UserProfile
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(profile: profile, size: 96)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.82), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
                    .accessibilityHidden(true)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Label("Edit Profile Photo", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .foregroundStyle(SettingsMonochromeDesign.primary)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.68), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.76), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
                        .pulsarLiquidGlass(
                            cornerRadius: 22,
                            tint: .white.opacity(0.12),
                            interactive: true
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 1, y: 1)
            }

            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                Label("Edit Photo", systemImage: "camera")
                    .font(.headline)
                    .foregroundStyle(SettingsMonochromeDesign.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(SettingsMonochromeDesign.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
