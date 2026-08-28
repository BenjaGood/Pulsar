@preconcurrency import AVFoundation
import SwiftUI

struct BarcodeScannerView: UIViewControllerRepresentable {
    var isTorchEnabled: Bool
    var onScan: @MainActor @Sendable (String, BarcodeSymbology) -> Void
    var onUnavailable: @MainActor @Sendable (String) -> Void
    var onTorchAvailabilityChanged: @MainActor @Sendable (Bool) -> Void

    func makeUIViewController(context: Context) -> BarcodeCaptureViewController {
        BarcodeCaptureViewController(
            onScan: { code, symbology in onScan(code, symbology) },
            onUnavailable: { message in onUnavailable(message) },
            onTorchAvailabilityChanged: { isAvailable in onTorchAvailabilityChanged(isAvailable) }
        )
    }

    func updateUIViewController(_ controller: BarcodeCaptureViewController, context: Context) {
        controller.setTorchEnabled(isTorchEnabled)
    }

    static func dismantleUIViewController(
        _ controller: BarcodeCaptureViewController,
        coordinator: Void
    ) {
        controller.stopCapture()
    }
}

@MainActor
final class BarcodeCaptureViewController: UIViewController {
    private let captureEngine = BarcodeCaptureEngine()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: captureEngine.captureSession)

    init(
        onScan: @escaping @MainActor @Sendable (String, BarcodeSymbology) -> Void,
        onUnavailable: @escaping @MainActor @Sendable (String) -> Void,
        onTorchAvailabilityChanged: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        super.init(nibName: nil, bundle: nil)

        captureEngine.onScan = { payload, symbology in
            Task { @MainActor in
                onScan(payload, symbology)
            }
        }
        captureEngine.onUnavailable = {
            Task { @MainActor in
                onUnavailable("The barcode scanner could not start. Check Camera access and try again.")
            }
        }
        captureEngine.onTorchAvailabilityChanged = { isAvailable in
            Task { @MainActor in
                onTorchAvailabilityChanged(isAvailable)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        captureEngine.startCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    func setTorchEnabled(_ enabled: Bool) {
        captureEngine.setTorchEnabled(enabled)
    }

    func stopCapture() {
        captureEngine.stopCapture()
    }
}

nonisolated private final class BarcodeCaptureEngine: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let captureSession = AVCaptureSession()

    var onScan: (@Sendable (String, BarcodeSymbology) -> Void)?
    var onUnavailable: (@Sendable () -> Void)?
    var onTorchAvailabilityChanged: (@Sendable (Bool) -> Void)?

    private let sessionQueue = DispatchQueue(label: "app.pulsar.barcode-camera", qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "app.pulsar.barcode-metadata", qos: .userInitiated)
    private var videoDevice: AVCaptureDevice?
    private var isConfigured = false
    private var requestedTorchState = false
    private var deliveredCodes: Set<String> = []

    func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSessionIfNeeded()
                guard !self.captureSession.isRunning else { return }
                self.captureSession.startRunning()
                self.applyTorchState(self.requestedTorchState)
            } catch {
                self.onUnavailable?()
            }
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestedTorchState = false
            self.applyTorchState(false)
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func setTorchEnabled(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestedTorchState = enabled
            self.applyTorchState(enabled)
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw BarcodeCaptureError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureMetadataOutput()

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
            throw BarcodeCaptureError.configurationFailed
        }
        captureSession.addInput(input)
        captureSession.addOutput(output)

        let requestedTypes: [AVMetadataObject.ObjectType] = [
            .upce, .ean8, .ean13, .code39, .code93, .code128, .itf14
        ]
        output.metadataObjectTypes = requestedTypes.filter(output.availableMetadataObjectTypes.contains)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)

        videoDevice = device
        isConfigured = true
        onTorchAvailabilityChanged?(device.hasTorch && device.isTorchAvailable)
    }

    private func applyTorchState(_ enabled: Bool) {
        guard let device = videoDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = enabled ? .on : .off
        } catch {
            onTorchAvailabilityChanged?(false)
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let barcode = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = barcode.stringValue,
              deliveredCodes.insert(payload).inserted else { return }
        onScan?(payload, Self.symbology(for: barcode.type))
    }

    private static func symbology(for value: AVMetadataObject.ObjectType) -> BarcodeSymbology {
        switch value {
        case .upce: .upcE
        case .ean8: .ean8
        case .ean13: .ean13
        case .itf14: .gtin14
        default: .unknown
        }
    }
}

nonisolated private enum BarcodeCaptureError: Error {
    case cameraUnavailable
    case configurationFailed
}
