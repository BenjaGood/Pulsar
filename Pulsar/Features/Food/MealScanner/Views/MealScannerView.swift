//
//  MealScannerView.swift
//  Pulsar
//

import AVFoundation
import ARKit
import OSLog
import SwiftUI
import UIKit

struct MealScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var nutritionStore: PulsarNutritionStore
    var initialCategoryID: UUID?

    @State private var captureController = MealScannerARCaptureController()
    @State private var scanPhase: ScanPhase = .intro
    @State private var scanMode: MealScanMode = MealScanProcessingService.supportsLiDARDepth ? .depthAssisted : .photoOnly
    @State private var startedAt: Date?
    @State private var result: MealScanResult?
    @State private var pendingClarificationResult: MealScanResult?
    @State private var errorMessage: String?
    @State private var liveFrameFeedback = MealScannerLiveFrameFeedback()
    @State private var guidedScanProgress = 0.0
    @State private var guidedScanStep: MealGuidedScanStep = .capturePhoto
    @State private var lidarScanState = MealLidarScanState()
    @State private var photoCapture: MealScannerPhotoCapture?
    @State private var frameFeedbackLogCounter = 0

    private let processingService = MealScanProcessingService()
    private let nutritionAIService: MealNutritionAIServicing
    private static let logger = Logger(subsystem: "tech.aetherial.pulsar", category: "MealScanner")

    init(
        nutritionStore: PulsarNutritionStore,
        initialCategoryID: UUID? = nil,
        nutritionAIService: MealNutritionAIServicing = MealNutritionAIService()
    ) {
        self.nutritionStore = nutritionStore
        self.initialCategoryID = initialCategoryID
        self.nutritionAIService = nutritionAIService
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let resultBinding {
                    MealScanResultView(
                        result: resultBinding,
                        nutritionStore: nutritionStore,
                        initialCategoryID: initialCategoryID,
                        onRescan: resetForRescan
                    )
                    .transition(.opacity)
                } else if scanPhase.usesCamera {
                    immersiveCameraContent
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 1.015))
                        )
                } else {
                    scannerContent
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.985))
                        )
                }
            }
            .animation(.smooth(duration: reduceMotion ? 0.20 : 0.42), value: scanPhase)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !scanPhase.usesCamera {
                        Button("Close meal scanner", systemImage: "xmark", action: closeScanner)
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Dismisses the meal scanner")
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(scanPhase.usesCamera ? .hidden : .visible, for: .navigationBar)
        .onDisappear {
            cancelGuidedScan()
        }
        .sheet(item: $pendingClarificationResult) { pendingResult in
            MealIngredientClarificationView(
                result: pendingResult,
                nutritionAIService: nutritionAIService
            ) { resolvedResult in
                completeClarifiedResult(resolvedResult)
            }
            .interactiveDismissDisabled(true)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var scannerContent: some View {
        MealScannerIntroView(
            isLiDARReady: scanMode == .depthAssisted,
            isStarting: scanPhase == .checkingPermission,
            errorMessage: errorMessage,
            onStart: primaryAction
        )
    }

    private var immersiveCameraContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            MealScannerARView(
                captureController: captureController,
                scanMode: scanMode,
                isSessionRunning: scanPhase.usesCamera,
                showsLiDARMesh: false,
                onFrameUpdate: handleFrameFeedback
            )
            .ignoresSafeArea()

            MealScannerCameraOverlay(
                model: cameraOverlayModel,
                onClose: closeScanner,
                onCapture: primaryAction
            )
        }
    }

    private var cameraOverlayModel: MealScannerCameraOverlay.Model {
        MealScannerCameraOverlay.Model(
            currentStep: cameraStep,
            selectedPhase: selectedCameraPhase,
            isLiDARAvailable: scanMode == .depthAssisted,
            guidance: cameraGuidance,
            scanProgress: cameraMapProgress,
            isAnalyzing: scanPhase == .analyzing,
            captureAccessibilityLabel: scanPhase.buttonTitle
        )
    }

    private var cameraMapProgress: Double {
        guard scanMode == .depthAssisted, photoCapture != nil else { return 0 }
        let lidarPortion = (guidedScanProgress - 0.16) / 0.84
        return min(max(lidarPortion, 0), 1)
    }

    private var cameraStep: Int {
        switch scanPhase {
        case .ready:
            1
        case .scanning:
            2
        case .complete, .analyzing:
            3
        case .intro, .checkingPermission, .error:
            1
        }
    }

    private var selectedCameraPhase: MealScannerCameraOverlay.CapturePhase {
        guard scanMode == .depthAssisted else { return .photo }
        return scanPhase == .ready ? .photo : .lidar
    }

    private var cameraGuidance: MealScannerCameraOverlay.Guidance {
        if scanPhase == .analyzing {
            return .init(
                symbolName: "sparkles",
                title: "Analyzing your meal",
                subtitle: "Keep the plate in view."
            )
        }

        if scanPhase == .complete {
            return .init(
                symbolName: "checkmark",
                title: "Scan complete",
                subtitle: "Ready to analyze your meal."
            )
        }

        if !liveFrameFeedback.isLightingReady {
            return .init(
                symbolName: "sun.max",
                title: "Find better light",
                subtitle: "Avoid strong shadows over the food."
            )
        }

        if !liveFrameFeedback.isTrackingReady {
            if liveFrameFeedback.trackingMessage.localizedCaseInsensitiveContains("slower") {
                return .init(
                    symbolName: "hand.raised",
                    title: "Move slowly",
                    subtitle: "Keep the phone steady while scanning."
                )
            }

            if liveFrameFeedback.trackingMessage.localizedCaseInsensitiveContains("edge") {
                return .init(
                    symbolName: "camera.metering.center.weighted",
                    title: "Keep the plate visible",
                    subtitle: "Include the plate edge and nearby table."
                )
            }

            return .init(
                symbolName: "hand.raised",
                title: "Hold steady",
                subtitle: "Let the camera find the plate."
            )
        }

        if scanMode == .depthAssisted,
           let distance = liveFrameFeedback.approximateSubjectDistance {
            if distance < 0.28 {
                return .init(
                    symbolName: "arrow.up.left.and.arrow.down.right",
                    title: "Move back slightly",
                    subtitle: "Keep the full plate in view."
                )
            }

            if distance > 1.25 {
                return .init(
                    symbolName: "arrow.down.right.and.arrow.up.left",
                    title: "Move closer",
                    subtitle: "Bring the meal into clearer view."
                )
            }
        }

        if scanPhase == .ready {
            return .init(
                symbolName: "camera.metering.center.weighted",
                title: "Capture the plate",
                subtitle: "Center the entire plate in good light."
            )
        }

        if scanPhase == .scanning, !liveFrameFeedback.hasDepth {
            return .init(
                symbolName: "move.3d",
                title: "Move closer",
                subtitle: "Keep the full plate in view."
            )
        }

        switch guidedScanStep {
        case .capturePhoto, .mapCenter:
            return .init(
                symbolName: "move.3d",
                title: "Scan around the plate",
                subtitle: "Move slowly around the meal."
            )
        case .moveLeft:
            return .init(
                symbolName: "arrow.left",
                title: "Scan one side",
                subtitle: "Keep the entire plate visible."
            )
        case .moveRight:
            return .init(
                symbolName: "arrow.right",
                title: "Move to the other side",
                subtitle: "Keep the entire plate visible."
            )
        case .tiltForward:
            return .init(
                symbolName: "arrow.down.forward",
                title: "Capture the height",
                subtitle: "Tilt slightly toward the meal."
            )
        case .holdSteady:
            return .init(
                symbolName: "circle.dotted",
                title: "Almost there",
                subtitle: "Capture the remaining side."
            )
        case .complete:
            return .init(
                symbolName: "checkmark",
                title: "Scan complete",
                subtitle: "Ready to analyze your meal."
            )
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
            completeGuidedScan()
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
        Self.logger.debug("Starting meal scan mode=\(scanMode.rawValue, privacy: .public) supportsLiDARDepth=\(MealScanProcessingService.supportsLiDARDepth, privacy: .public)")
        playImpact(.soft)

        let status = MealScanProcessingService.cameraAuthorizationStatus()
        Self.logger.debug("Meal scanner camera authorization status=\(String(describing: status), privacy: .public)")
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
            Self.logger.error("Meal scanner camera permission denied")
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
        Self.logger.debug("Starting meal scan analysis mode=\(scanMode.rawValue, privacy: .public) hasStoredPhoto=\(photoCapture != nil, privacy: .public)")
        playImpact(.medium)
        let duration = Date().timeIntervalSince(startedAt ?? Date())

        do {
            let storedCapture = photoCapture
            let liveCapture = storedCapture == nil ? captureController.captureImage() : nil
            guard let analysisImage = storedCapture?.image ?? liveCapture?.image else {
                Self.logger.error("Meal scan analysis aborted: missing analysis image")
                errorMessage = "Pulsar could not capture a camera frame. Move the phone slightly and try again."
                scanPhase = .error
                playNotification(.error)
                return
            }
            let analysisFrame = captureController.currentFrameSnapshot() ?? storedCapture?.frame ?? liveCapture?.frame
            Self.logger.debug("Meal scan payload capture imageSource=\(storedCapture == nil ? "live" : "stored", privacy: .public) hasFrame=\(analysisFrame != nil, privacy: .public)")
            let scanSession = lidarScanState.summary(photoCaptured: storedCapture != nil || liveCapture != nil, mode: scanMode)
            let payload = try processingService.makePayload(
                from: analysisImage,
                frame: analysisFrame,
                scanMode: scanMode,
                scanDuration: duration,
                scanSession: scanSession,
                accumulator: captureController.frameAccumulator,
                calibrationStore: MealScanCalibrationStore.shared
            )
            let imageBase64 = try processingService.preparedJPEGBase64(from: analysisImage)
            Self.logger.debug("Meal scan request prepared imageBase64Bytes=\(imageBase64.count, privacy: .public) duration=\(duration, privacy: .public) depthCompleted=\(scanSession.depthScanCompleted, privacy: .public)")
            var analyzedResult = try await nutritionAIService.analyzeMeal(imageBase64: imageBase64, payload: payload)
            analyzedResult.mode = scanMode
            if analyzedResult.accuracyDisclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                analyzedResult.accuracyDisclaimer = MealScanResultMetadata().disclaimer
            }
            Self.logger.debug("Meal scan analysis succeeded title=\(analyzedResult.title, privacy: .public) ingredients=\(analyzedResult.ingredients.count, privacy: .public) model=\(analyzedResult.metadata.modelName ?? "unknown", privacy: .public)")
            if analyzedResult.hasUnresolvedAmbiguousIngredients {
                pendingClarificationResult = analyzedResult
                scanPhase = .intro
                resetGuidedScanState()
            } else {
                result = analyzedResult
                scanPhase = .intro
                resetGuidedScanState()
            }
        } catch {
            Self.logger.error("Meal scan analysis failed type=\(String(describing: type(of: error)), privacy: .public) description=\(((error as? LocalizedError)?.errorDescription ?? error.localizedDescription), privacy: .public)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            scanPhase = .error
            playNotification(.error)
        }
    }

    private func resetForRescan() {
        result = nil
        pendingClarificationResult = nil
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

    private func completeClarifiedResult(_ resolvedResult: MealScanResult) {
        pendingClarificationResult = nil
        result = resolvedResult
        scanPhase = .intro
        resetGuidedScanState()
        playNotification(.success)
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
        frameFeedbackLogCounter += 1

        withAnimation(.linear(duration: 0.16)) {
            guidedScanProgress = lidarScanState.progress
            guidedScanStep = lidarScanState.currentStep
        }

        logLidarProgressIfNeeded(previousStep: previousStep, previousMilestone: previousMilestone)

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
            Self.logger.error("Meal scanner reference photo capture failed mode=\(scanMode.rawValue, privacy: .public)")
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
        Self.logger.debug("Meal scanner reference photo captured mode=\(scanMode.rawValue, privacy: .public) hasFrame=true branch=\(scanMode == .depthAssisted ? "guided" : "complete", privacy: .public)")

        if scanMode == .depthAssisted {
            beginGuidedScan()
        } else {
            completeGuidedScan()
        }
    }

    private func beginGuidedScan() {
        cancelGuidedScan()
        lidarScanState.reset()
        captureController.startAccumulating()
        guidedScanProgress = 0.16
        guidedScanStep = .mapCenter
        errorMessage = nil
        frameFeedbackLogCounter = 0
        Self.logger.debug("LiDAR guided meal scan started")

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            scanPhase = .scanning
        }
        playImpact(.medium)
    }

    private func completeGuidedScan() {
        cancelGuidedScan()
        captureController.stopAccumulating()
        Self.logger.debug("Completing guided meal scan progress=\(lidarScanState.progress, privacy: .public) acceptedFrames=\(lidarScanState.acceptedFrameCount, privacy: .public) stableFrames=\(lidarScanState.stableFrameCount, privacy: .public) points=\(lidarScanState.pointCloud.count, privacy: .public) coverage=\(lidarScanState.coverageRatio, privacy: .public) coveredCells=\(lidarScanState.coveredCellRatio, privacy: .public) movement=\(lidarScanState.movementScore, privacy: .public) automaticThreshold=\(lidarScanState.isComplete, privacy: .public) keyFrames=\(captureController.frameAccumulator.frameCount, privacy: .public)")
        guidedScanProgress = lidarScanState.isComplete ? 1 : lidarScanState.progress
        guidedScanStep = .complete
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            scanPhase = .complete
        }
        playNotification(.success)
    }

    private func cancelGuidedScan() {
        captureController.stopAccumulating()
    }

    private func logLidarProgressIfNeeded(previousStep: MealGuidedScanStep, previousMilestone: Int) {
        guard frameFeedbackLogCounter.isMultiple(of: 30)
                || guidedScanStep != previousStep
                || lidarScanState.milestone > previousMilestone
                || lidarScanState.isComplete else {
            return
        }

        Self.logger.debug("LiDAR meal scan progress=\(lidarScanState.progress, privacy: .public) step=\(lidarScanState.currentStep.rawValue, privacy: .public) acceptedFrames=\(lidarScanState.acceptedFrameCount, privacy: .public) stableFrames=\(lidarScanState.stableFrameCount, privacy: .public) points=\(lidarScanState.pointCloud.count, privacy: .public) coverage=\(lidarScanState.coverageRatio, privacy: .public) coveredCells=\(lidarScanState.coveredCellRatio, privacy: .public) movement=\(lidarScanState.movementScore, privacy: .public) isComplete=\(lidarScanState.isComplete, privacy: .public)")
    }

    private func resetGuidedScanState() {
        cancelGuidedScan()
        guidedScanProgress = 0
        guidedScanStep = .capturePhoto
        lidarScanState.reset()
        captureController.resetAccumulator()
        photoCapture = nil
    }

    private func playImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func playNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
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

    var buttonTitle: String {
        switch self {
        case .intro, .error: "Start Scan"
        case .checkingPermission: "Checking..."
        case .ready: "Capture Photo"
        case .scanning: "Finish Scan"
        case .complete: "Analyze Meal"
        case .analyzing: "Analyzing..."
        }
    }
}

private enum MealGuidedScanStep: String {
    case capturePhoto
    case mapCenter
    case moveLeft
    case moveRight
    case tiltForward
    case holdSteady
    case complete

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

    nonisolated private static func cellIndex(for point: MealScannerDepthPoint) -> Int? {
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

#Preview {
    MealScannerView(
        nutritionStore: PulsarNutritionStore(provider: PulsarNutritionLocalProvider(fileStore: PulsarNutritionFileStore(directoryURL: FileManager.default.temporaryDirectory)))
    )
}

#Preview("Meal Scanner — 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    MealScannerView(
        nutritionStore: PulsarNutritionStore(provider: PulsarNutritionLocalProvider(fileStore: PulsarNutritionFileStore(directoryURL: FileManager.default.temporaryDirectory)))
    )
}
