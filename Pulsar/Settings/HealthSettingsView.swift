//
//  HealthSettingsView.swift
//  Pulsar
//

import SwiftUI

struct HealthSettingsView: View {
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    var onAuthorizationUpdated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isRequestingAuthorization = false
    @State private var isShowingAuthorizationError = false
    @State private var isShowingConnectionManagement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HealthSettingsDesign.sectionSpacing) {
                HealthSettingsHeader()

                PulsarGlassEffectGroup(spacing: HealthSettingsDesign.sectionSpacing) {
                    HealthConnectionCard(
                        permissionState: healthKitStore.permissionState,
                        isRequestingAuthorization: isRequestingAuthorization,
                        errorMessage: healthKitStore.lastErrorMessage,
                        connect: connectAppleHealth,
                        manage: showConnectionManagement
                    )
                }

                if dynamicTypeSize.isAccessibilitySize {
                    HealthPrivacyFooter()
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: HealthSettingsDesign.maximumContentWidth)
            .padding(.horizontal, HealthSettingsDesign.horizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(HealthSettingsDesign.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                HealthSettingsBackButton(action: dismissHealthSettings)
                Spacer()
            }
            .padding(.horizontal, HealthSettingsDesign.horizontalPadding)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                HealthPrivacyFooter()
                    .padding(.horizontal, HealthSettingsDesign.horizontalPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .animation(stateAnimation, value: healthKitStore.permissionState)
        .onAppear(perform: healthKitStore.refreshStatus)
        .alert("Couldn’t Connect to Apple Health", isPresented: $isShowingAuthorizationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(healthKitStore.lastErrorMessage ?? "Please review Pulsar’s access in Apple Health and try again.")
        }
        .confirmationDialog(
            "Manage Apple Health access?",
            isPresented: $isShowingConnectionManagement,
            titleVisibility: .visible
        ) {
            Button("Open Settings", action: openSystemSettings)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Apple controls Health permissions. Open Settings to review or change Pulsar’s access.")
        }
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }

    private var stateAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)
    }

    private func connectAppleHealth() {
        guard !isRequestingAuthorization else { return }

        isRequestingAuthorization = true
        Task {
            await healthKitStore.requestAuthorization()
            isRequestingAuthorization = false

            if healthKitStore.permissionState.isConnected {
                onAuthorizationUpdated?()
            } else if healthKitStore.lastErrorMessage != nil {
                isShowingAuthorizationError = true
            }
        }
    }

    private func showConnectionManagement() {
        isShowingConnectionManagement = true
    }

    private func dismissHealthSettings() {
        dismiss()
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }
}

#Preview("Health Permissions") {
    NavigationStack {
        HealthSettingsView(
            healthKitStore: connectedHealthPermissionsPreviewStore()
        )
    }
}

@MainActor
private func connectedHealthPermissionsPreviewStore() -> HealthKitSettingsStore {
    let defaults = UserDefaults(suiteName: "pulsar.health-permissions.preview") ?? .standard
    let lifecycleStore = AppLifecycleStore(defaults: defaults)
    lifecycleStore.hasSeenHealthKitOnboarding = true
    return HealthKitSettingsStore(lifecycleStore: lifecycleStore)
}
