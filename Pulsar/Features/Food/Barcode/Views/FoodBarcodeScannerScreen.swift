import SwiftUI

struct FoodBarcodeScannerScreen: View {
    var model: FoodBarcodeFlowModel
    var backAction: () -> Void
    var manualEntryAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BarcodeScannerView(
                    isTorchEnabled: model.isTorchEnabled,
                    onScan: model.received,
                    onUnavailable: model.scannerUnavailable,
                    onTorchAvailabilityChanged: model.setTorchAvailability
                )
                .ignoresSafeArea()

                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 16) {
                        scannerControls(in: proxy)
                    }
                } else {
                    scannerControls(in: proxy)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Barcode scanner")
    }

    @ViewBuilder
    private func scannerControls(in proxy: GeometryProxy) -> some View {
        let topInset = max(proxy.safeAreaInsets.top + 12, 24)
        let bottomInset = max(proxy.safeAreaInsets.bottom + 12, 18)
        let frameWidth = min(proxy.size.width - 48, 360)
        let frameHeight = min(max(proxy.size.height * 0.46, 350), 500)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: backAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 56, height: 56)
                }
                .scannerGlassCircle()
                .accessibilityLabel("Back")

                Text("Scan Barcode")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .frame(height: 58)
                    .scannerGlassCapsule()
                    .accessibilityAddTraits(.isHeader)

                Color.clear.frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, topInset)

            HStack(spacing: 10) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 17, weight: .medium))
                Text("Align the barcode inside the frame")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
            .scannerGlassCapsule()
            .padding(.top, 28)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 18)

            BarcodeScannerGuide(
                size: CGSize(width: frameWidth, height: frameHeight),
                reduceMotion: reduceMotion
            )
            .accessibilityHidden(true)

            Spacer(minLength: 18)

            Button(action: model.toggleTorch) {
                Image(systemName: model.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 60, height: 60)
            }
            .scannerGlassCircle()
            .disabled(!model.isTorchAvailable)
            .opacity(model.isTorchAvailable ? 1 : 0.45)
            .accessibilityLabel(model.isTorchEnabled ? "Turn flashlight off" : "Turn flashlight on")
            .sensoryFeedback(.impact(flexibility: .soft), trigger: model.isTorchEnabled)

            Button(action: manualEntryAction) {
                HStack(spacing: 16) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: 56, height: 56)
                        .scannerGlassCircle()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter barcode manually")
                            .font(.system(.title3, design: .rounded, weight: .medium))
                        Text("Type the barcode number")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 112)
                .scannerGlassRounded(cornerRadius: 34)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, bottomInset)
            .accessibilityLabel("Enter barcode manually")
            .accessibilityHint("Type the barcode number")
        }
        .foregroundStyle(.white)
    }
}

private struct BarcodeScannerGuide: View {
    var size: CGSize
    var reduceMotion: Bool

    @State private var lineProgress = 0.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)

            ScannerCornerBracket()
                .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 76, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScannerCornerBracket()
                .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: 76, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            ScannerCornerBracket()
                .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(180))
                .frame(width: 76, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            ScannerCornerBracket()
                .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(270))
                .frame(width: 76, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            Rectangle()
                .fill(.white.opacity(0.78))
                .frame(height: 1)
                .shadow(color: .white.opacity(0.45), radius: 5)
                .offset(y: reduceMotion ? 0 : (lineProgress - 0.5) * (size.height - 24))
                .padding(.horizontal, 2)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            lineProgress = 0
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                lineProgress = 1
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                lineProgress = 0.5
            } else {
                withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                    lineProgress = 1
                }
            }
        }
    }
}

private struct ScannerCornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + 16, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + 16, y: rect.minY + 16),
            radius: 16,
            startAngle: .degrees(-90),
            endAngle: .degrees(-180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

private extension View {
    @ViewBuilder
    func scannerGlassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear.tint(.white.opacity(0.018)).interactive(), in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
        }
    }

    @ViewBuilder
    func scannerGlassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear.tint(.white.opacity(0.018)).interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
        }
    }

    @ViewBuilder
    func scannerGlassRounded(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear.tint(.white.opacity(0.018)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        }
    }
}
