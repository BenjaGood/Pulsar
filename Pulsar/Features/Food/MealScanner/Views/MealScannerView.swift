//
//  MealScannerView.swift
//  Pulsar
//

import AVFoundation
import ARKit
import SwiftUI
import UIKit

struct MealScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var nutritionStore: PulsarNutritionStore

    @State private var captureController = MealScannerARCaptureController()
    @State private var scanPhase: ScanPhase = .intro
    @State private var scanMode: MealScanMode = MealScanProcessingService.supportsLiDARDepth ? .depthAssisted : .photoOnly
    @State private var startedAt: Date?
    @State private var result: MealScanResult?
    @State private var errorMessage: String?
    @State private var liveFrameFeedback = MealScannerLiveFrameFeedback()
    @State private var guidedScanProgress = 0.0
    @State private var guidedScanStep: MealGuidedScanStep = .capturePhoto
    @State private var lidarScanState = MealLidarScanState()
    @State private var photoCapture: MealScannerPhotoCapture?

    private let processingService = MealScanProcessingService()
    private let nutritionAIService: MealNutritionAIServicing

    init(
        nutritionStore: PulsarNutritionStore,
        nutritionAIService: MealNutritionAIServicing = MealNutritionAIService()
    ) {
        self.nutritionStore = nutritionStore
        self.nutritionAIService = nutritionAIService
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let resultBinding {
                    MealScanResultView(
                        result: resultBinding,
                        nutritionStore: nutritionStore,
                        onRescan: resetForRescan
                    )
                } else if scanPhase.usesCamera {
                    immersiveCameraContent
                } else {
                    PulsarSectionBackground()
                    scannerContent
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !scanPhase.usesCamera {
                        Button(action: closeScanner) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .pulsarLiquidGlass(cornerRadius: 19)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close meal scanner")
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            cancelGuidedScan()
        }
    }

    private var scannerContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    scannerSurface(height: scannerHeight(in: proxy))
                    if !scanPhase.usesCamera {
                        guidanceCard
                    }
                    statusCard
                    actionButton

                    if let errorMessage {
                        errorCard(errorMessage)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, proxy.safeAreaInsets.top + 18)
                .padding(.bottom, 38)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var immersiveCameraContent: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                MealScannerARView(
                    captureController: captureController,
                    scanMode: scanMode,
                    isSessionRunning: scanPhase.usesCamera,
                    showsLiDARMesh: scanPhase == .scanning || scanPhase == .complete,
                    onFrameUpdate: handleFrameFeedback
                )
                .ignoresSafeArea()

                cameraReadabilityGradient
                    .ignoresSafeArea()

                MealScannerReticleView(isActive: scanPhase == .scanning || scanPhase == .complete)
                    .padding(.horizontal, 34)
                    .padding(.top, proxy.safeAreaInsets.top + 138)
                    .padding(.bottom, 210)

                VStack(spacing: 0) {
                    immersiveCameraTopBar(safeAreaTop: proxy.safeAreaInsets.top)
                    Spacer(minLength: 0)
                    immersiveCameraBottomPanel(safeAreaBottom: proxy.safeAreaInsets.bottom)
                }
            }
        }
    }

    private func immersiveCameraTopBar(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: closeScanner) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.54), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close meal scanner")

                VStack(alignment: .leading, spacing: 3) {
                    Text("3D Meal Scanner")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                    Text(immersiveStatusText)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer(minLength: 0)

                Text(scanPhase.surfaceLabel)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(scanPhase.tint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(scanPhase.tint.opacity(0.18), in: Capsule(style: .continuous))
            }

            HStack(spacing: 8) {
                liveStatusChip(
                    title: liveFrameFeedback.trackingTitle,
                    symbolName: "scope",
                    tint: liveFrameFeedback.isTrackingReady ? .green : .orange
                )
                liveStatusChip(
                    title: lidarStatusTitle,
                    symbolName: liveFrameFeedback.hasDepth ? "viewfinder.circle.fill" : "camera.fill",
                    tint: liveFrameFeedback.hasDepth ? .cyan : .orange
                )
                liveStatusChip(
                    title: liveFrameFeedback.lightingTitle,
                    symbolName: liveFrameFeedback.isLightingReady ? "sun.max.fill" : "lightbulb.max.fill",
                    tint: liveFrameFeedback.isLightingReady ? .green : .orange
                )
            }
        }
        .padding(.top, safeAreaTop + 12)
        .padding(.horizontal, 18)
    }

    private func immersiveCameraBottomPanel(safeAreaBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MealScannerPhaseRail(
                photoStatus: photoCapture == nil ? .active : .complete,
                lidarStatus: lidarPhaseStatus
            )

            scanProgressHeader

            VStack(alignment: .leading, spacing: 10) {
                Text(currentGuidanceTitle)
                    .pulsarTextStyle(.sectionTitle)
                    .foregroundStyle(.white)
                Text(currentGuidanceSubtitle)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            MealScannerStepTimeline(
                activeStep: guidedScanStep,
                progress: guidedScanProgress,
                isComplete: scanPhase == .complete
            )

            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if scanPhase == .analyzing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: scanPhase.buttonSymbolName)
                    }
                    Text(scanPhase.buttonTitle)
                }
                .pulsarTextStyle(.buttonTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: scanPhase == .complete ? .green : .cyan))
            .disabled(!scanPhase.canTapPrimary)
        }
        .padding(14)
        .padding(.bottom, max(safeAreaBottom, 12))
        .background(.black.opacity(0.58), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
        }
    }

    private var scanProgressHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(scanPhase == .complete ? "Scan complete" : "Building 3D map", systemImage: scanPhase == .complete ? "checkmark.circle.fill" : "dot.viewfinder")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(scanPhase == .complete ? .green : .white)

                Spacer(minLength: 10)

                Text("\(Int((guidedScanProgress * 100).rounded()))%")
                    .pulsarTextStyle(.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.70))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.16))
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * guidedScanProgress))
                }
            }
            .frame(height: 7)
        }
    }

    private func liveStatusChip(title: String, symbolName: String, tint: Color) -> some View {
        Label(title, systemImage: symbolName)
            .pulsarTextStyle(.overline)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.34), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.cyan, .green)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("3D Meal Scanner")
                        .pulsarTextStyle(.displayLarge)
                        .foregroundStyle(.primary)
                    Text("LiDAR, image analysis, and AI nutrition estimates.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                }
            }

            MealScannerCapabilityPill(
                title: scanMode == .depthAssisted ? "LiDAR depth enabled" : "Photo AI estimation mode",
                symbolName: scanMode == .depthAssisted ? "viewfinder.circle.fill" : "camera.fill",
                tint: scanMode == .depthAssisted ? .cyan : .orange
            )
        }
    }

    private func scannerSurface(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.black.opacity(0.36))

            if scanPhase.usesCamera {
                MealScannerARView(
                    captureController: captureController,
                    scanMode: scanMode,
                    isSessionRunning: scanPhase.usesCamera,
                    showsLiDARMesh: scanPhase == .scanning || scanPhase == .complete
                )
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(cameraReadabilityGradient)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 42, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.92), .cyan.opacity(0.74))
                    Text("Position your plate in good light")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white.opacity(0.88))
                    Text("Pulsar captures a clear photo first, then maps the plate with LiDAR when available.")
                        .pulsarTextStyle(.captionEmphasis)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 28)
                }
            }

            MealScannerReticleView(isActive: scanPhase == .scanning)
                .padding(30)

            if scanPhase.usesCamera {
                VStack {
                    Spacer()
                    activeCameraInstructionCard
                }
                .padding(16)
            }

            VStack {
                HStack {
                    Spacer()
                    Text(scanPhase.surfaceLabel)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.34), in: Capsule(style: .continuous))
                }
                Spacer()
            }
            .padding(18)
        }
        .frame(height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 16)
    }

    private var cameraReadabilityGradient: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.22),
                .black.opacity(0.04),
                .black.opacity(0.62)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var activeCameraInstructionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeCameraInstructionSymbol)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(scanPhase.tint)
                    .frame(width: 30, height: 30)
                    .background(scanPhase.tint.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeCameraInstructionTitle)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                    Text(activeCameraInstructionSubtitle)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(activeCameraInstructions.enumerated()), id: \.offset) { index, instruction in
                    MealScannerInstructionRow(number: index + 1, text: instruction)
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var guidanceCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(
                    title: "Two-phase scan",
                    subtitle: "Photo first, LiDAR mapping second"
                )

                Text("Capture a clear photo for food identity, then move slowly while LiDAR fills the plate map. Pulsar marks the scan complete only after enough depth coverage is collected.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(estimateMethodText). For medical or strict diet tracking, verify with a food scale.")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.orange.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            HStack(spacing: 12) {
                scannerStatusIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(scanPhase.title)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.primary)
                    Text(scanPhase.subtitle(for: scanMode))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var scannerStatusIcon: some View {
        ZStack {
            Circle()
                .fill(scanPhase.tint.opacity(0.16))
            Image(systemName: scanPhase.symbolName)
                .pulsarTextStyle(.cardTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(scanPhase.tint)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var actionButton: some View {
        Button(action: primaryAction) {
            HStack(spacing: 10) {
                if scanPhase == .checkingPermission || scanPhase == .analyzing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: scanPhase.buttonSymbolName)
                }
                Text(scanPhase.buttonTitle)
            }
            .pulsarTextStyle(.buttonTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(NutritionActionButtonStyle(tint: scanPhase == .error ? .orange : .green))
        .disabled(!scanPhase.canTapPrimary)
    }

    private func errorCard(_ message: String) -> some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultBinding: Binding<MealScanResult>? {
        guard result != nil else { return nil }
        return Binding(
            get: { result ?? fallbackResult },
            set: { result = $0 }
        )
    }

    private var fallbackResult: MealScanResult {
        MealNutritionAIService.mockResult(
            payload: MealScanPayload(
                metadata: MealScanCaptureMetadata(mode: scanMode, imageWidth: 0, imageHeight: 0, imageOrientation: "up"),
                quality: MealScanQuality(level: .usable, confidence: 0.5)
            )
        )
    }

    private func scannerHeight(in proxy: GeometryProxy) -> CGFloat {
        if scanPhase.usesCamera {
            return min(650, max(500, proxy.size.height * 0.68))
        }
        return min(520, max(360, proxy.size.height * 0.48))
    }

    private var estimateMethodText: String {
        scanMode == .depthAssisted
            ? "Estimated using image + depth analysis"
            : "Estimated using photo AI analysis"
    }

    private func primaryAction() {
        switch scanPhase {
        case .intro, .error:
            Task { await startScan() }
        case .ready:
            captureReferencePhoto()
        case .scanning:
            break
        case .complete:
            Task { await captureAndAnalyze() }
        case .checkingPermission, .analyzing:
            break
        }
    }

    private func startScan() async {
        errorMessage = nil
        resetGuidedScanState()
        scanMode = MealScanProcessingService.supportsLiDARDepth ? .depthAssisted : .photoOnly
        scanPhase = .checkingPermission
        playImpact(.soft)

        let status = MealScanProcessingService.cameraAuthorizationStatus()
        let isAuthorized: Bool
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await MealScanProcessingService.requestCameraAccess()
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else {
            errorMessage = "Camera permission is required to scan meals. Enable camera access in Settings and try again."
            scanPhase = .error
            playNotification(.warning)
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            scanPhase = .ready
        }
        playImpact(.light)
    }

    private func captureAndAnalyze() async {
        cancelGuidedScan()
        scanPhase = .analyzing
        playImpact(.medium)
        let duration = Date().timeIntervalSince(startedAt ?? Date())

        do {
            let storedCapture = photoCapture
            let liveCapture = storedCapture == nil ? captureController.captureImage() : nil
            guard let analysisImage = storedCapture?.image ?? liveCapture?.image else {
                errorMessage = "Pulsar could not capture a camera frame. Move the phone slightly and try again."
                scanPhase = .error
                playNotification(.error)
                return
            }
            let analysisFrame = captureController.currentFrameSnapshot() ?? storedCapture?.frame ?? liveCapture?.frame
            let scanSession = lidarScanState.summary(photoCaptured: storedCapture != nil || liveCapture != nil, mode: scanMode)
            let payload = try processingService.makePayload(
                from: analysisImage,
                frame: analysisFrame,
                scanMode: scanMode,
                scanDuration: duration,
                scanSession: scanSession
            )
            let imageBase64 = try processingService.preparedJPEGBase64(from: analysisImage)
            var analyzedResult = try await nutritionAIService.analyzeMeal(imageBase64: imageBase64, payload: payload)
            analyzedResult.mode = scanMode
            if analyzedResult.accuracyDisclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                analyzedResult.accuracyDisclaimer = MealScanResultMetadata().disclaimer
            }
            result = analyzedResult
            scanPhase = .intro
            resetGuidedScanState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            scanPhase = .error
            playNotification(.error)
        }
    }

    private func resetForRescan() {
        result = nil
        errorMessage = nil
        scanPhase = .ready
        startedAt = nil
        resetGuidedScanState()
        playImpact(.soft)
    }

    private func closeScanner() {
        cancelGuidedScan()
        playImpact(.light)
        dismiss()
    }

    private func handleFrameFeedback(_ feedback: MealScannerLiveFrameFeedback) {
        let frameChanged = feedback != liveFrameFeedback
        if frameChanged {
            liveFrameFeedback = feedback
        }

        guard scanPhase == .scanning else { return }
        let previousStep = guidedScanStep
        let previousMilestone = lidarScanState.milestone
        lidarScanState.record(feedback)

        withAnimation(.linear(duration: 0.16)) {
            guidedScanProgress = lidarScanState.progress
            guidedScanStep = lidarScanState.currentStep
        }

        if guidedScanStep != previousStep {
            playImpact(.light)
        }
        if lidarScanState.milestone > previousMilestone {
            playImpact(.soft)
        }
        if lidarScanState.isComplete {
            completeGuidedScan()
        }
    }

    private func captureReferencePhoto() {
        guard let capture = captureController.captureImage() else {
            errorMessage = "Pulsar could not capture the plate photo. Center the plate and try again."
            scanPhase = .error
            playNotification(.error)
            return
        }

        photoCapture = MealScannerPhotoCapture(image: capture.image, frame: capture.frame)
        startedAt = Date()
        errorMessage = nil
        guidedScanProgress = 0.16
        guidedScanStep = scanMode == .depthAssisted ? .mapCenter : .complete
        playNotification(.success)

        if scanMode == .depthAssisted {
            beginGuidedScan()
        } else {
            completeGuidedScan()
        }
    }

    private func beginGuidedScan() {
        cancelGuidedScan()
        lidarScanState.reset()
        guidedScanProgress = 0.16
        guidedScanStep = .mapCenter
        errorMessage = nil

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            scanPhase = .scanning
        }
        playImpact(.medium)
    }

    private func completeGuidedScan() {
        guidedScanProgress = 1
        guidedScanStep = .complete
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            scanPhase = .complete
        }
        playNotification(.success)
    }

    private func cancelGuidedScan() {}

    private func resetGuidedScanState() {
        cancelGuidedScan()
        guidedScanProgress = 0
        guidedScanStep = .capturePhoto
        lidarScanState.reset()
        photoCapture = nil
    }

    private func playImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func playNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private func status(for step: MealGuidedScanStep) -> MealGuidedScanStepRow.Status {
        if scanPhase == .complete || step.progressEnd <= guidedScanProgress {
            return .complete
        }
        if step == guidedScanStep {
            return .active
        }
        return .pending
    }

    private var immersiveStatusText: String {
        if scanPhase == .complete {
            return "Ready to analyze"
        }
        if scanPhase == .scanning {
            return liveFrameFeedback.isCaptureReady ? "LiDAR map \(Int((lidarScanState.progress * 100).rounded()))% built" : "\(liveFrameFeedback.trackingMessage). \(liveFrameFeedback.lightingMessage)."
        }
        return liveFrameFeedback.isCaptureReady ? "Phase 1: capture photo" : "\(liveFrameFeedback.trackingMessage). \(liveFrameFeedback.lightingMessage)."
    }

    private var lidarStatusTitle: String {
        guard scanMode == .depthAssisted else { return "Photo only" }
        if scanPhase == .scanning || scanPhase == .complete {
            return "\(Int((lidarScanState.progress * 100).rounded()))% built"
        }
        return liveFrameFeedback.hasDepth ? "Depth ready" : "Depth pending"
    }

    private var currentGuidanceTitle: String {
        if scanPhase == .complete {
            return "Scan complete"
        }
        if scanPhase == .ready {
            return "Phase 1: capture the plate"
        }
        return guidedScanStep.title
    }

    private var currentGuidanceSubtitle: String {
        if scanPhase == .complete {
            return "Great. Keep the plate in frame and tap Analyze Meal."
        }
        if scanPhase == .ready {
            return "Center the full plate in good light. This photo is the visual evidence the AI will analyze."
        }
        if !liveFrameFeedback.isCaptureReady {
            return "\(liveFrameFeedback.trackingMessage). \(liveFrameFeedback.lightingMessage)."
        }
        return guidedScanStep.instruction
    }

    private var lidarPhaseStatus: MealScannerPhaseRail.Status {
        if scanPhase == .complete || lidarScanState.isComplete {
            return .complete
        }
        if scanPhase == .scanning {
            return .active
        }
        return photoCapture == nil ? .pending : .active
    }

    private var activeCameraInstructionTitle: String {
        switch scanPhase {
        case .ready:
            "Capture photo"
        case .scanning:
            "Map with LiDAR"
        case .complete:
            "Scan complete"
        case .analyzing:
            "Hold steady"
        case .intro, .checkingPermission, .error:
            "Frame the full plate"
        }
    }

    private var activeCameraInstructionSubtitle: String {
        switch scanPhase {
        case .ready:
            "Phase 1"
        case .scanning:
            "Phase 2"
        case .complete:
            "Ready to analyze"
        case .analyzing:
            "Estimating portions"
        case .intro, .checkingPermission, .error:
            "Scanner guide"
        }
    }

    private var activeCameraInstructionSymbol: String {
        switch scanPhase {
        case .ready:
            "scope"
        case .scanning:
            "dot.viewfinder"
        case .complete:
            "checkmark.circle.fill"
        case .analyzing:
            "sparkles"
        case .intro, .checkingPermission, .error:
            "camera.viewfinder"
        }
    }

    private var activeCameraInstructions: [String] {
        switch scanPhase {
        case .ready:
            [
                "Center the whole plate.",
                "Use bright, even light.",
                "Tap Capture Photo before moving."
            ]
        case .scanning:
            [
                "Watch the LiDAR mesh attach to the plate and food.",
                "Move left, right, then tilt for tall food.",
                "Pulsar will mark complete automatically."
            ]
        case .complete:
            [
                "Scan complete.",
                "Keep the plate in frame.",
                "Tap Analyze Meal to estimate nutrition."
            ]
        case .analyzing:
            [
                "Keep the app open while Pulsar estimates portions.",
                "You will be able to edit grams before saving."
            ]
        case .intro, .checkingPermission, .error:
            [
                "Use bright, even light.",
                "Keep the whole plate visible."
            ]
        }
    }
}

private enum ScanPhase: Equatable {
    case intro
    case checkingPermission
    case ready
    case scanning
    case complete
    case analyzing
    case error

    var usesCamera: Bool {
        switch self {
        case .ready, .scanning, .complete, .analyzing:
            true
        case .intro, .checkingPermission, .error:
            false
        }
    }

    var title: String {
        switch self {
        case .intro: "Ready when you are"
        case .checkingPermission: "Checking camera access"
        case .ready: "Camera ready"
        case .scanning: "Move slowly around the plate"
        case .complete: "Scan complete"
        case .analyzing: "Estimating nutrition"
        case .error: "Needs attention"
        }
    }

    func subtitle(for mode: MealScanMode) -> String {
        switch self {
        case .intro:
            mode == .depthAssisted ? "This iPhone can use depth-assisted scanning." : "This iPhone will use photo-only AI estimation."
        case .checkingPermission:
            "Pulsar asks only when you open the scanner."
        case .ready:
            "Phase 1: capture a clear photo before LiDAR mapping."
        case .scanning:
            "Phase 2: LiDAR mapping is building coverage from real depth frames."
        case .complete:
            "Enough coverage captured. Analyze when the plate is still in frame."
        case .analyzing:
            "Sending a compact image and depth summary to the backend."
        case .error:
            "You can retry after adjusting permission, lighting, or framing."
        }
    }

    var buttonTitle: String {
        switch self {
        case .intro, .error: "Start Scan"
        case .checkingPermission: "Checking..."
        case .ready: "Capture Photo"
        case .scanning: "Scanning..."
        case .complete: "Analyze Meal"
        case .analyzing: "Analyzing..."
        }
    }

    var buttonSymbolName: String {
        switch self {
        case .intro, .error, .ready: "camera.fill"
        case .checkingPermission, .analyzing: "hourglass"
        case .scanning: "dot.viewfinder"
        case .complete: "sparkles"
        }
    }

    var symbolName: String {
        switch self {
        case .intro: "viewfinder"
        case .checkingPermission: "lock.shield"
        case .ready: "camera.fill"
        case .scanning: "dot.viewfinder"
        case .complete: "checkmark.circle.fill"
        case .analyzing: "sparkles"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var surfaceLabel: String {
        switch self {
        case .intro: "Setup"
        case .checkingPermission: "Permission"
        case .ready: "Camera"
        case .scanning: "Scanning"
        case .complete: "Complete"
        case .analyzing: "Analyzing"
        case .error: "Paused"
        }
    }

    var tint: Color {
        switch self {
        case .intro, .ready: .cyan
        case .checkingPermission, .analyzing: .green
        case .scanning: .mint
        case .complete: .green
        case .error: .orange
        }
    }

    var canTapPrimary: Bool {
        switch self {
        case .checkingPermission, .scanning, .analyzing:
            false
        case .intro, .ready, .complete, .error:
            true
        }
    }
}

private enum MealGuidedScanStep: String, CaseIterable, Identifiable {
    case capturePhoto
    case mapCenter
    case moveLeft
    case moveRight
    case tiltForward
    case holdSteady
    case complete

    var id: String { rawValue }

    static let scanSequence: [MealGuidedScanStep] = [
        .capturePhoto,
        .mapCenter,
        .moveLeft,
        .moveRight,
        .tiltForward,
        .holdSteady
    ]

    static func step(for progress: Double) -> MealGuidedScanStep {
        switch progress {
        case ..<0.16:
            .capturePhoto
        case ..<0.34:
            .mapCenter
        case ..<0.52:
            .moveLeft
        case ..<0.70:
            .moveRight
        case ..<0.88:
            .tiltForward
        case ..<1:
            .holdSteady
        default:
            .complete
        }
    }

    var progressEnd: Double {
        switch self {
        case .capturePhoto: 0.16
        case .mapCenter: 0.34
        case .moveLeft: 0.52
        case .moveRight: 0.70
        case .tiltForward: 0.88
        case .holdSteady, .complete: 1.0
        }
    }

    var title: String {
        switch self {
        case .capturePhoto:
            "Photo captured"
        case .mapCenter:
            "Map the plate center"
        case .moveLeft:
            "Scan one side"
        case .moveRight:
            "Scan the opposite side"
        case .tiltForward:
            "Tilt slightly forward"
        case .holdSteady:
            "Hold steady"
        case .complete:
            "Scan complete"
        }
    }

    var instruction: String {
        switch self {
        case .capturePhoto:
            "Use this clear photo as the visual evidence for food identity."
        case .mapCenter:
            "Hold above the plate until the center fills with depth points."
        case .moveLeft:
            "Slide to one side so LiDAR sees the edge of the food."
        case .moveRight:
            "Slide to the opposite side without cropping the plate."
        case .tiltForward:
            "Tilt slightly forward so tall portions get depth."
        case .holdSteady:
            "Pause until Pulsar gets a stable final depth frame."
        case .complete:
            "Coverage is complete. Analyze the meal."
        }
    }

    var symbolName: String {
        switch self {
        case .capturePhoto:
            "camera.fill"
        case .mapCenter:
            "viewfinder"
        case .moveLeft:
            "arrow.left"
        case .moveRight:
            "arrow.right"
        case .tiltForward:
            "arrow.down.forward"
        case .holdSteady:
            "pause.circle.fill"
        case .complete:
            "checkmark.circle.fill"
        }
    }
}

private struct MealScannerPhotoCapture {
    var image: UIImage
    var frame: ARFrame?
}

private struct MealLidarScanState {
    private(set) var coverageCells = Array(repeating: 0.0, count: MealScannerDepthGrid.cellCount)
    private var cellHitCounts = Array(repeating: 0, count: MealScannerDepthGrid.cellCount)
    private var lastAcceptedPose: MealScannerCameraPose?
    private var originPose: MealScannerCameraPose?
    private var readyFrameCount = 0
    private(set) var depthFrameCount = 0
    private(set) var acceptedFrameCount = 0
    private(set) var stableFrameCount = 0
    private(set) var movementScore = 0.0
    private(set) var pointCloud: [MealScannerDepthPoint] = []
    private(set) var progress = 0.16
    private(set) var currentStep: MealGuidedScanStep = .mapCenter
    private(set) var milestone = 0
    private(set) var isComplete = false

    var coverageRatio: Double {
        guard !coverageCells.isEmpty else { return 0 }
        return coverageCells.reduce(0, +) / Double(coverageCells.count)
    }

    var coveredCellRatio: Double {
        guard !coverageCells.isEmpty else { return 0 }
        let coveredCells = coverageCells.filter { $0 >= 0.75 }.count
        return Double(coveredCells) / Double(coverageCells.count)
    }

    mutating func reset() {
        coverageCells = Array(repeating: 0, count: MealScannerDepthGrid.cellCount)
        cellHitCounts = Array(repeating: 0, count: MealScannerDepthGrid.cellCount)
        lastAcceptedPose = nil
        originPose = nil
        readyFrameCount = 0
        depthFrameCount = 0
        acceptedFrameCount = 0
        stableFrameCount = 0
        movementScore = 0
        pointCloud = []
        progress = 0.16
        currentStep = .mapCenter
        milestone = 0
        isComplete = false
    }

    mutating func record(_ feedback: MealScannerLiveFrameFeedback) {
        guard !isComplete else { return }

        guard feedback.isCaptureReady, feedback.hasDepth else {
            stableFrameCount = 0
            currentStep = .mapCenter
            return
        }

        readyFrameCount += 1
        depthFrameCount += feedback.depthCoverage >= 0.10 ? 1 : 0
        stableFrameCount = feedback.depthCoverage >= 0.18 && feedback.depthPoints.count >= 28 ? stableFrameCount + 1 : 0

        guard shouldAccept(feedback) else {
            updateProgress()
            return
        }

        acceptedFrameCount += 1
        if originPose == nil {
            originPose = feedback.cameraPose
        }
        movementScore = min(movementScore + scanMotionDelta(from: lastAcceptedPose, to: feedback.cameraPose), 1)
        lastAcceptedPose = feedback.cameraPose

        for index in observedCellIndexes(from: feedback) {
            cellHitCounts[index] = min(cellHitCounts[index] + 1, 4)
            coverageCells[index] = min(Double(cellHitCounts[index]) / 4.0, 1)
        }

        appendPointCloud(from: feedback)
        updateProgress()
    }

    private mutating func updateProgress() {
        let frameScore = min(Double(acceptedFrameCount) / 9, 1)
        let stabilityScore = min(Double(stableFrameCount) / 12, 1)
        let coverageScore = min(((coverageRatio / 0.32) * 0.58) + ((coveredCellRatio / 0.32) * 0.42), 1)
        let densityScore = min(Double(pointCloud.count) / 360, 1)
        let motionScore = min(movementScore / 0.55, 1)
        progress = min(0.98, 0.16 + (coverageScore * 0.20) + (frameScore * 0.18) + (stabilityScore * 0.10) + (densityScore * 0.22) + (motionScore * 0.14))
        currentStep = MealGuidedScanStep.step(for: progress)
        milestone = Int((progress * 5).rounded(.down))

        let hasEnoughGeometry = pointCloud.count >= 260 && (coverageRatio >= 0.18 || coveredCellRatio >= 0.18)
        if hasEnoughGeometry,
           acceptedFrameCount >= 6,
           stableFrameCount >= 8,
           movementScore >= 0.22 {
            isComplete = true
            progress = 1
            currentStep = .complete
            milestone = 5
        }
    }

    private func shouldAccept(_ feedback: MealScannerLiveFrameFeedback) -> Bool {
        guard feedback.depthCoverage >= 0.10, feedback.depthPoints.count >= 22 else { return false }
        guard let pose = feedback.cameraPose else {
            return readyFrameCount == 1 || (acceptedFrameCount < 4 && readyFrameCount.isMultiple(of: 18))
        }
        guard let lastAcceptedPose else { return true }
        let movedEnough = pose.distance(to: lastAcceptedPose) >= 0.045
        let turnedEnough = pose.yawDelta(to: lastAcceptedPose) >= 0.095
        let warmupSample = acceptedFrameCount < 4 && readyFrameCount.isMultiple(of: 18)
        return movedEnough || turnedEnough || warmupSample
    }

    private func scanMotionDelta(from previous: MealScannerCameraPose?, to current: MealScannerCameraPose?) -> Double {
        guard let current else { return previous == nil ? 0.10 : 0 }
        guard let previous else { return 0.12 }
        let distanceScore = min(current.distance(to: previous) * 3.2, 0.22)
        let yawScore = min(current.yawDelta(to: previous) * 1.4, 0.20)
        return max(distanceScore, yawScore)
    }

    private func observedCellIndexes(from feedback: MealScannerLiveFrameFeedback) -> Set<Int> {
        let cellsFromPoints = Set(feedback.depthPoints.compactMap(Self.cellIndex(for:)))
        if !cellsFromPoints.isEmpty {
            return cellsFromPoints
        }

        return Set(feedback.depthCoverageGrid.enumerated().compactMap { index, coverage in
            coverage >= 0.16 ? index : nil
        })
    }

    private static func cellIndex(for point: MealScannerDepthPoint) -> Int? {
        let normalizedX = min(max((point.x + 1) / 2, 0), 0.999)
        let normalizedY = min(max((point.y + 1) / 2, 0), 0.999)
        let cellX = Int(normalizedX * Double(MealScannerDepthGrid.columns))
        let cellY = Int(normalizedY * Double(MealScannerDepthGrid.rows))
        let index = (cellY * MealScannerDepthGrid.columns) + cellX
        guard index >= 0, index < MealScannerDepthGrid.cellCount else { return nil }
        return index
    }

    private mutating func appendPointCloud(from feedback: MealScannerLiveFrameFeedback) {
        guard !feedback.depthPoints.isEmpty else { return }
        let stride = max(1, feedback.depthPoints.count / 70)
        let offset = mapOffset(for: feedback.cameraPose)
        let sampled = feedback.depthPoints.enumerated().compactMap { index, point -> MealScannerDepthPoint? in
            guard index.isMultiple(of: stride) else { return nil }
            return point.offset(x: offset.x, y: offset.y)
        }
        pointCloud.append(contentsOf: sampled)
        if pointCloud.count > 720 {
            pointCloud.removeFirst(pointCloud.count - 720)
        }
    }

    private func mapOffset(for pose: MealScannerCameraPose?) -> (x: Double, y: Double) {
        guard let pose, let originPose else { return (0, 0) }
        return (
            x: min(max((pose.x - originPose.x) * 1.8, -0.34), 0.34),
            y: min(max((pose.z - originPose.z) * 1.8, -0.34), 0.34)
        )
    }

    func summary(photoCaptured: Bool, mode: MealScanMode) -> MealScanSessionSummary {
        MealScanSessionSummary(
            photoCaptured: photoCaptured,
            depthScanCompleted: mode == .depthAssisted ? isComplete : true,
            coverageRatio: mode == .depthAssisted ? coverageRatio : 0,
            coveredCellRatio: mode == .depthAssisted ? coveredCellRatio : 0,
            depthFrameCount: mode == .depthAssisted ? acceptedFrameCount : 0,
            stableFrameCount: mode == .depthAssisted ? stableFrameCount : 0,
            coverageGridColumns: MealScannerDepthGrid.columns,
            coverageGridRows: MealScannerDepthGrid.rows
        )
    }
}

private struct MealScannerPhaseRail: View {
    enum Status {
        case pending
        case active
        case complete
    }

    var photoStatus: Status
    var lidarStatus: Status

    var body: some View {
        HStack(spacing: 8) {
            phasePill(title: "1 Photo", symbolName: "camera.fill", status: photoStatus, tint: .cyan)
            phasePill(title: "2 LiDAR", symbolName: "viewfinder.circle.fill", status: lidarStatus, tint: .mint)
        }
    }

    private func phasePill(title: String, symbolName: String, status: Status, tint: Color) -> some View {
        Label(title, systemImage: status == .complete ? "checkmark.circle.fill" : symbolName)
            .pulsarTextStyle(.overline)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .foregroundStyle(foregroundColor(status: status, tint: tint))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(backgroundColor(status: status, tint: tint), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(foregroundColor(status: status, tint: tint).opacity(0.22), lineWidth: 1)
            }
    }

    private func foregroundColor(status: Status, tint: Color) -> Color {
        switch status {
        case .pending:
            .white.opacity(0.44)
        case .active:
            tint
        case .complete:
            .green
        }
    }

    private func backgroundColor(status: Status, tint: Color) -> Color {
        switch status {
        case .pending:
            .white.opacity(0.06)
        case .active:
            tint.opacity(0.14)
        case .complete:
            Color.green.opacity(0.14)
        }
    }
}

private struct MealScannerStepTimeline: View {
    var activeStep: MealGuidedScanStep
    var progress: Double
    var isComplete: Bool

    var body: some View {
        HStack(spacing: 7) {
            ForEach(MealGuidedScanStep.scanSequence) { step in
                Capsule(style: .continuous)
                    .fill(color(for: step))
                    .frame(maxWidth: .infinity)
                    .frame(height: step == activeStep && !isComplete ? 8 : 5)
                    .overlay {
                        if step == activeStep && !isComplete {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.34), lineWidth: 1)
                        }
                    }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityLabel("Meal scan progress \(Int((progress * 100).rounded())) percent")
    }

    private func color(for step: MealGuidedScanStep) -> Color {
        if isComplete || step.progressEnd <= progress {
            return .green.opacity(0.76)
        }
        if step == activeStep {
            return .cyan.opacity(0.86)
        }
        return .white.opacity(0.16)
    }
}

private struct MealScannerPointCloudOverlay: View {
    var points: [MealScannerDepthPoint]
    var livePoints: [MealScannerDepthPoint]
    var coverageCells: [Double]
    var columns: Int
    var progress: Double
    var acceptedFrameCount: Int
    var isActive: Bool

    var body: some View {
        if isActive {
            ZStack {
                Canvas { context, size in
                    drawScanSurface(in: &context, size: size)
                    drawPoints(in: &context, size: size, points: visiblePoints)
                }

                if visiblePoints.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "dot.viewfinder")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.cyan.opacity(0.82))
                        Text("Move slowly to paint the plate")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.horizontal, 18)
                    .multilineTextAlignment(.center)
                }

                VStack {
                    Spacer(minLength: 0)
                    coverageRibbon
                }
                .padding(10)
            }
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.cyan.opacity(0.18), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Label("3D map", systemImage: "point.3.connected.trianglepath.dotted")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.36), in: Capsule(style: .continuous))
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(min(acceptedFrameCount, 99)) keyframes")
                    .pulsarTextStyle(.overline)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.36), in: Capsule(style: .continuous))
                    .padding(8)
            }
            .accessibilityHidden(true)
        }
    }

    private var visiblePoints: [MealScannerDepthPoint] {
        let combined = Array(points.suffix(420)) + Array(livePoints.prefix(50))
        return Array(combined.suffix(470))
    }

    private var coverageRibbon: some View {
        HStack(spacing: 2) {
            ForEach(Array(coverageCells.enumerated()), id: \.offset) { _, coverage in
                Capsule(style: .continuous)
                    .fill(cellColor(for: coverage))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
        }
        .frame(height: 7)
        .overlay(alignment: .trailing) {
            Text("\(Int((progress * 100).rounded()))%")
                .pulsarTextStyle(.overline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .padding(.leading, 8)
                .background(.black.opacity(0.46))
        }
    }

    private func drawScanSurface(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
        let plateRect = CGRect(
            x: center.x - (size.width * 0.34),
            y: center.y - (size.height * 0.20),
            width: size.width * 0.68,
            height: size.height * 0.34
        )
        let plate = Path(ellipseIn: plateRect)
        context.stroke(plate, with: .color(.white.opacity(0.22)), lineWidth: 1.2)

        let innerPlate = Path(ellipseIn: plateRect.insetBy(dx: plateRect.width * 0.14, dy: plateRect.height * 0.18))
        context.stroke(innerPlate, with: .color(.cyan.opacity(0.20)), lineWidth: 1)

        let gridColor = Color.white.opacity(0.09)
        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 14, y: size.height * (0.22 + (fraction * 0.56))))
            horizontal.addLine(to: CGPoint(x: size.width - 14, y: size.height * (0.18 + (fraction * 0.50))))
            context.stroke(horizontal, with: .color(gridColor), lineWidth: 0.8)
        }
        for step in 0...5 {
            let fraction = CGFloat(step) / 5
            var vertical = Path()
            vertical.move(to: CGPoint(x: size.width * (0.14 + fraction * 0.72), y: size.height * 0.18))
            vertical.addLine(to: CGPoint(x: size.width * (0.22 + fraction * 0.56), y: size.height * 0.82))
            context.stroke(vertical, with: .color(gridColor), lineWidth: 0.8)
        }
    }

    private func drawPoints(in context: inout GraphicsContext, size: CGSize, points: [MealScannerDepthPoint]) {
        for point in points.sorted(by: { $0.z > $1.z }) {
            let location = projected(point, in: size)
            let radius = CGFloat(1.35 + (point.confidence * 1.35) + ((1 - point.normalizedDepth) * 0.7))
            let rect = CGRect(
                x: location.x - radius,
                y: location.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let color = pointColor(for: point)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.56)))
        }
    }

    private func projected(_ point: MealScannerDepthPoint, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.62)
        let depth = CGFloat(point.normalizedDepth)
        let perspective = 1 / (1 + (depth * 0.72))
        let projectedX = center.x
            + (CGFloat(point.x) * size.width * 0.34 * perspective)
            + ((depth - 0.5) * size.width * 0.08)
        let projectedY = center.y
            + (CGFloat(point.y) * size.height * 0.23 * perspective)
            - (depth * size.height * 0.28)
        return CGPoint(
            x: min(max(projectedX, 12), size.width - 12),
            y: min(max(projectedY, 16), size.height - 18)
        )
    }

    private func pointColor(for point: MealScannerDepthPoint) -> Color {
        if point.confidence > 0.72 {
            return .green
        }
        if point.confidence > 0.42 {
            return .cyan
        }
        return .orange
    }

    private func cellColor(for coverage: Double) -> Color {
        switch coverage {
        case 0.75...:
            .green.opacity(0.54)
        case 0.40..<0.75:
            .cyan.opacity(0.42)
        case 0.10..<0.40:
            .cyan.opacity(0.18)
        default:
            .white.opacity(0.055)
        }
    }
}

private struct MealGuidedScanStepRow: View {
    enum Status {
        case pending
        case active
        case complete
    }

    var step: MealGuidedScanStep
    var status: Status

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(symbolColor)
                .frame(width: 24, height: 24)
                .background(symbolColor.opacity(status == .pending ? 0.08 : 0.18), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(textColor)
                if status == .active {
                    Text(step.instruction)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, status == .active ? 9 : 7)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var symbolName: String {
        switch status {
        case .pending:
            step.symbolName
        case .active:
            "dot.radiowaves.left.and.right"
        case .complete:
            "checkmark"
        }
    }

    private var symbolColor: Color {
        switch status {
        case .pending:
            .white.opacity(0.42)
        case .active:
            .cyan
        case .complete:
            .green
        }
    }

    private var textColor: Color {
        switch status {
        case .pending:
            .white.opacity(0.48)
        case .active, .complete:
            .white.opacity(0.90)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .pending:
            .white.opacity(0.045)
        case .active:
            .cyan.opacity(0.14)
        case .complete:
            .green.opacity(0.12)
        }
    }
}

private struct MealScannerReticleView: View {
    var isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.16 : 0.10), style: StrokeStyle(lineWidth: 1.4, dash: [10, 12]))

            VStack {
                HStack {
                    corner
                    Spacer()
                    corner.rotationEffect(.degrees(90))
                }
                Spacer()
                HStack {
                    corner.rotationEffect(.degrees(-90))
                    Spacer()
                    corner.rotationEffect(.degrees(180))
                }
            }
            .padding(12)
        }
        .animation(.easeInOut(duration: 0.28), value: isActive)
        .accessibilityHidden(true)
    }

    private var corner: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 22))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 22, y: 0))
        }
        .stroke(.green.opacity(isActive ? 0.82 : 0.48), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        .frame(width: 22, height: 22)
    }
}

private struct MealScannerInstructionRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .pulsarTextStyle(.overline)
                .foregroundStyle(.black.opacity(0.78))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.88), in: Circle())

            Text(text)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    MealScannerView(
        nutritionStore: PulsarNutritionStore(provider: PulsarNutritionLocalProvider(fileStore: PulsarNutritionFileStore(directoryURL: FileManager.default.temporaryDirectory)))
    )
}
