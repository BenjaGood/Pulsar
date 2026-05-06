//
//  ProfileView.swift
//  Pulsar
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    var body: some View {
        ProfileDetailsView(store: store, onSave: onSave)
    }
}

#Preview("Profile Details Wrapper") {
    NavigationStack {
        ProfileView(store: SettingsPreviewStore.make())
    }
}

#Preview("Profile Avatar") {
    AvatarView(profile: MockHealthData.profile, size: 56)
        .padding(8)
        .pulsarLiquidGlass(cornerRadius: 36)
        .padding()
        .background(PulsarSectionBackground())
}
