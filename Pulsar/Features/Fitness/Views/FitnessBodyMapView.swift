//
//  FitnessBodyMapView.swift
//  Pulsar
//

import SceneKit
import SwiftUI

struct FitnessBodyMapSection: View {
    var analysis: BodyMapAnalysis

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ZStack(alignment: .bottom) {
                HumanBodyTrainingSceneView(analysis: analysis)
                    .frame(height: 318)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(modelBorder, lineWidth: 1)
                    }

                HStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .font(.caption.weight(.bold))
                    Text("Drag to rotate")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(colorScheme == .dark ? 0.24 : 0.10), in: Capsule(style: .continuous))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .padding(.bottom, 12)
            }

            insightCard
        }
        .padding(18)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(sectionBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 22, y: 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: analysis)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Body Map")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(primaryText)

                Text("Weekly training zones")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(analysis.isCardioActive ? BodyZone.heart.accent : secondaryText.opacity(0.42))
                    .frame(width: 8, height: 8)
                    .shadow(color: (analysis.isCardioActive ? BodyZone.heart.accent : .clear).opacity(0.55), radius: 8)

                Text(analysis.isCardioActive ? "Active" : "Inactive")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(analysis.isCardioActive ? BodyZone.heart.accent : secondaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(statusBackground, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(statusBorder, lineWidth: 1)
            }
        }
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle()
                    .fill(BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.18 : 0.08))
                    .frame(width: 46, height: 46)

                Image(systemName: analysis.isCardioActive ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(analysis.isCardioActive ? BodyZone.heart.accent : secondaryText)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(analysis.isCardioActive ? "Cardio active" : "No cardio logged")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(primaryText)

                Text(insightText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(insightBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 1)
        }
    }

    private var insightText: String {
        guard analysis.cardioSessions > 0 else {
            return "Start a cardio workout to activate your heart zone."
        }

        let sessionCopy = analysis.cardioSessions == 1 ? "session" : "sessions"
        let duration = FitnessWeekFormatters.duration(analysis.cardioDuration)
        return "You completed \(analysis.cardioSessions) cardio \(sessionCopy) this week - \(duration) total."
    }

    private var sectionBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.86),
                    BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.10 : 0.035)
                ]
                : [
                    Color.white.opacity(0.92),
                    Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.76),
                    BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.08 : 0.025)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var insightBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.09), Color.white.opacity(0.035), BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.09 : 0.025)]
                : [Color.white.opacity(0.86), Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.68), BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.06 : 0.02)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.11), Color.white.opacity(0.04), BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.10 : 0)]
                : [Color.white.opacity(0.84), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.62), BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.06 : 0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sectionBorder: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.18 : 0.82),
                BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.24 : 0.08),
                .black.opacity(colorScheme == .dark ? 0.22 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusBorder: Color {
        analysis.isCardioActive
            ? BodyZone.heart.accent.opacity(colorScheme == .dark ? 0.30 : 0.22)
            : .white.opacity(colorScheme == .dark ? 0.12 : 0.68)
    }

    private var modelBorder: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.13 : 0.70),
                BodyZone.heart.accent.opacity(analysis.isCardioActive ? 0.20 : 0.06),
                .cyan.opacity(colorScheme == .dark ? 0.10 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

struct HumanBodyTrainingSceneView: UIViewRepresentable {
    var analysis: BodyMapAnalysis

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView(initialAnalysis: analysis)
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(analysis: analysis, in: view)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let bodyRoot = SCNNode()
        private let cameraNode = SCNNode()
        private var zoneNodes: [BodyZone: [SCNNode]] = [:]
        private var heartPulseNode: SCNNode?
        private var rotationX: Float = -0.08
        private var rotationY: Float = -0.28
        private var cameraDistance: Float = 5.5

        func makeView(initialAnalysis: BodyMapAnalysis) -> SCNView {
            let view = SCNView(frame: .zero)
            let scene = SCNScene()

            view.scene = scene
            view.backgroundColor = .clear
            view.isOpaque = false
            view.antialiasingMode = .multisampling4X
            view.rendersContinuously = initialAnalysis.isCardioActive
            view.isPlaying = initialAnalysis.isCardioActive
            view.preferredFramesPerSecond = 60

            configureCamera(in: scene)
            configureLighting(in: scene)
            configureBody(in: scene)
            configureGestures(for: view)
            update(analysis: initialAnalysis, in: view)

            return view
        }

        func update(analysis: BodyMapAnalysis, in view: SCNView) {
            view.rendersContinuously = analysis.isCardioActive
            view.isPlaying = analysis.isCardioActive

            for zone in BodyZone.allCases {
                let trainedZone = analysis.trainedZone(for: zone)
                let isActive = trainedZone != nil
                let intensity = trainedZone?.intensity ?? 0

                zoneNodes[zone]?.forEach { node in
                    node.geometry?.materials = [material(for: zone, isActive: isActive, intensity: intensity)]
                }
            }

            updateHeartPulse(isActive: analysis.isCardioActive, intensity: analysis.trainedZone(for: .heart)?.intensity ?? 0)
        }

        private func configureCamera(in scene: SCNScene) {
            let camera = SCNCamera()
            camera.fieldOfView = 34
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0.45, cameraDistance)
            cameraNode.look(at: SCNVector3(0, 0.35, 0))
            scene.rootNode.addChildNode(cameraNode)
        }

        private func configureLighting(in scene: SCNScene) {
            scene.lightingEnvironment.intensity = 1.0

            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .omni
            keyLight.light?.intensity = 740
            keyLight.light?.color = UIColor(red: 0.70, green: 0.86, blue: 1.00, alpha: 1)
            keyLight.position = SCNVector3(-1.9, 2.8, 2.4)
            scene.rootNode.addChildNode(keyLight)

            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .omni
            rimLight.light?.intensity = 540
            rimLight.light?.color = UIColor(red: 1.00, green: 0.33, blue: 0.46, alpha: 1)
            rimLight.position = SCNVector3(1.8, 1.4, -1.8)
            scene.rootNode.addChildNode(rimLight)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 110
            ambient.light?.color = UIColor(white: 0.85, alpha: 1)
            scene.rootNode.addChildNode(ambient)
        }

        private func configureBody(in scene: SCNScene) {
            bodyRoot.eulerAngles = SCNVector3(rotationX, rotationY, 0)
            scene.rootNode.addChildNode(bodyRoot)

            addNeutralNode(geometry: SCNSphere(radius: 0.24), position: SCNVector3(0, 1.88, 0), scale: SCNVector3(0.88, 1.05, 0.82))
            addNeutralNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.24), position: SCNVector3(0, 1.58, 0))

            addZone(.shoulders, geometry: SCNCapsule(capRadius: 0.105, height: 1.08), position: SCNVector3(0, 1.40, 0), eulerAngles: SCNVector3(0, 0, Float.pi / 2))
            addZone(.chest, geometry: SCNSphere(radius: 0.36), position: SCNVector3(0, 1.05, 0.13), scale: SCNVector3(1.14, 0.82, 0.48))
            addZone(.back, geometry: SCNSphere(radius: 0.34), position: SCNVector3(0, 0.98, -0.16), scale: SCNVector3(1.05, 0.96, 0.42))
            addZone(.core, geometry: SCNCapsule(capRadius: 0.235, height: 0.60), position: SCNVector3(0, 0.48, 0.08), scale: SCNVector3(0.92, 1.0, 0.55))

            addZone(.biceps, geometry: SCNCapsule(capRadius: 0.095, height: 0.74), position: SCNVector3(-0.65, 0.86, 0.10), eulerAngles: SCNVector3(0, 0, 0.12))
            addZone(.biceps, geometry: SCNCapsule(capRadius: 0.095, height: 0.74), position: SCNVector3(0.65, 0.86, 0.10), eulerAngles: SCNVector3(0, 0, -0.12))
            addZone(.triceps, geometry: SCNCapsule(capRadius: 0.087, height: 0.72), position: SCNVector3(-0.69, 0.86, -0.10), eulerAngles: SCNVector3(0, 0, 0.10))
            addZone(.triceps, geometry: SCNCapsule(capRadius: 0.087, height: 0.72), position: SCNVector3(0.69, 0.86, -0.10), eulerAngles: SCNVector3(0, 0, -0.10))

            addZone(.glutes, geometry: SCNSphere(radius: 0.19), position: SCNVector3(-0.16, 0.10, -0.17), scale: SCNVector3(1.0, 0.75, 0.78))
            addZone(.glutes, geometry: SCNSphere(radius: 0.19), position: SCNVector3(0.16, 0.10, -0.17), scale: SCNVector3(1.0, 0.75, 0.78))
            addZone(.quads, geometry: SCNCapsule(capRadius: 0.125, height: 0.78), position: SCNVector3(-0.18, -0.42, 0.10))
            addZone(.quads, geometry: SCNCapsule(capRadius: 0.125, height: 0.78), position: SCNVector3(0.18, -0.42, 0.10))
            addZone(.hamstrings, geometry: SCNCapsule(capRadius: 0.118, height: 0.76), position: SCNVector3(-0.18, -0.42, -0.11))
            addZone(.hamstrings, geometry: SCNCapsule(capRadius: 0.118, height: 0.76), position: SCNVector3(0.18, -0.42, -0.11))
            addZone(.calves, geometry: SCNCapsule(capRadius: 0.098, height: 0.66), position: SCNVector3(-0.18, -1.12, 0.01))
            addZone(.calves, geometry: SCNCapsule(capRadius: 0.098, height: 0.66), position: SCNVector3(0.18, -1.12, 0.01))

            addHeartZone()
            addScanRings()
        }

        private func addZone(
            _ zone: BodyZone,
            geometry: SCNGeometry,
            position: SCNVector3,
            eulerAngles: SCNVector3 = SCNVector3Zero,
            scale: SCNVector3 = SCNVector3(1, 1, 1)
        ) {
            let node = SCNNode(geometry: geometry)
            node.name = zone.rawValue
            node.position = position
            node.eulerAngles = eulerAngles
            node.scale = scale
            node.geometry?.materials = [material(for: zone, isActive: false, intensity: 0)]
            bodyRoot.addChildNode(node)
            zoneNodes[zone, default: []].append(node)
        }

        private func addNeutralNode(
            geometry: SCNGeometry,
            position: SCNVector3,
            eulerAngles: SCNVector3 = SCNVector3Zero,
            scale: SCNVector3 = SCNVector3(1, 1, 1)
        ) {
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.eulerAngles = eulerAngles
            node.scale = scale
            node.geometry?.materials = [neutralMaterial(alpha: 0.32)]
            bodyRoot.addChildNode(node)
        }

        private func addHeartZone() {
            addZone(.heart, geometry: SCNSphere(radius: 0.105), position: SCNVector3(0.105, 1.12, 0.42), scale: SCNVector3(1.0, 1.08, 0.78))

            let pulse = SCNNode(geometry: SCNSphere(radius: 0.18))
            pulse.name = "heartPulse"
            pulse.position = SCNVector3(0.105, 1.12, 0.42)
            pulse.scale = SCNVector3(1.0, 1.08, 0.78)
            pulse.opacity = 0.18
            pulse.geometry?.materials = [pulseMaterial(isActive: false, intensity: 0)]
            bodyRoot.addChildNode(pulse)
            heartPulseNode = pulse
        }

        private func addScanRings() {
            for (index, yPosition) in [-1.46, -0.05, 0.72, 1.32].enumerated() {
                let torus = SCNTorus(ringRadius: index == 0 ? 0.88 : 0.62, pipeRadius: 0.004)
                let ring = SCNNode(geometry: torus)
                ring.position = SCNVector3(0, Float(yPosition), 0)
                ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                ring.opacity = index == 0 ? 0.46 : 0.25
                ring.geometry?.materials = [scanMaterial]
                bodyRoot.addChildNode(ring)
            }
        }

        private func configureGestures(for view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)

            rotationY += Float(translation.x) * 0.008
            rotationX = clamp(rotationX + Float(translation.y) * 0.004, min: -0.42, max: 0.34)
            bodyRoot.eulerAngles = SCNVector3(rotationX, rotationY, 0)
            gesture.setTranslation(.zero, in: view)

            guard gesture.state == .ended else { return }
            let velocity = gesture.velocity(in: view)
            let inertialTurn = clamp(Float(velocity.x) * 0.00018, min: -0.42, max: 0.42)
            rotationY += inertialTurn

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            bodyRoot.eulerAngles = SCNVector3(rotationX, rotationY, 0)
            SCNTransaction.commit()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            cameraDistance = clamp(cameraDistance / Float(gesture.scale), min: 4.35, max: 6.8)
            cameraNode.position.z = cameraDistance
            gesture.scale = 1
        }

        @objc private func resetCamera() {
            rotationX = -0.08
            rotationY = -0.28
            cameraDistance = 5.5

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.52
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bodyRoot.eulerAngles = SCNVector3(rotationX, rotationY, 0)
            cameraNode.position.z = cameraDistance
            SCNTransaction.commit()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = gestureRecognizer.view else {
                return true
            }

            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y) * 0.85
        }

        private func updateHeartPulse(isActive: Bool, intensity: Double) {
            guard let heartPulseNode else { return }

            heartPulseNode.geometry?.materials = [pulseMaterial(isActive: isActive, intensity: intensity)]
            heartPulseNode.removeAllActions()

            if isActive {
                heartPulseNode.opacity = CGFloat(0.26 + intensity * 0.22)
                let expand = SCNAction.group([
                    .scale(to: CGFloat(1.22 + intensity * 0.24), duration: 1.08),
                    .fadeOpacity(to: CGFloat(0.10 + intensity * 0.08), duration: 1.08)
                ])
                let reset = SCNAction.group([
                    .scale(to: 0.96, duration: 0.01),
                    .fadeOpacity(to: CGFloat(0.30 + intensity * 0.22), duration: 0.01)
                ])
                let wait = SCNAction.wait(duration: 0.24)
                heartPulseNode.runAction(.repeatForever(.sequence([reset, expand, wait])))
            } else {
                heartPulseNode.opacity = 0.16
                heartPulseNode.scale = SCNVector3(1.0, 1.08, 0.78)
            }
        }

        private func material(for zone: BodyZone, isActive: Bool, intensity: Double) -> SCNMaterial {
            let material = SCNMaterial()
            let zoneColor = uiColor(for: zone)
            material.lightingModel = .physicallyBased
            material.blendMode = .alpha
            material.isDoubleSided = true
            material.diffuse.contents = isActive
                ? zoneColor.withAlphaComponent(CGFloat(0.58 + intensity * 0.26))
                : UIColor(red: 0.58, green: 0.70, blue: 0.82, alpha: 0.24)
            material.emission.contents = isActive
                ? zoneColor.withAlphaComponent(CGFloat(0.20 + intensity * 0.38))
                : UIColor(red: 0.35, green: 0.48, blue: 0.58, alpha: 0.07)
            material.metalness.contents = isActive ? 0.20 : 0.08
            material.roughness.contents = isActive ? 0.34 : 0.58
            material.transparency = isActive ? CGFloat(0.78 + intensity * 0.16) : 0.38
            return material
        }

        private func neutralMaterial(alpha: CGFloat) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.blendMode = .alpha
            material.isDoubleSided = true
            material.diffuse.contents = UIColor(red: 0.64, green: 0.74, blue: 0.84, alpha: alpha)
            material.emission.contents = UIColor(red: 0.30, green: 0.42, blue: 0.52, alpha: 0.05)
            material.metalness.contents = 0.10
            material.roughness.contents = 0.56
            material.transparency = alpha
            return material
        }

        private func pulseMaterial(isActive: Bool, intensity: Double) -> SCNMaterial {
            let material = SCNMaterial()
            let color = uiColor(for: .heart)
            material.lightingModel = .constant
            material.blendMode = .add
            material.isDoubleSided = true
            material.diffuse.contents = color.withAlphaComponent(isActive ? CGFloat(0.18 + intensity * 0.22) : 0.08)
            material.emission.contents = color.withAlphaComponent(isActive ? CGFloat(0.35 + intensity * 0.38) : 0.07)
            material.transparency = isActive ? CGFloat(0.32 + intensity * 0.28) : 0.14
            return material
        }

        private var scanMaterial: SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.blendMode = .add
            material.diffuse.contents = UIColor(red: 0.44, green: 0.92, blue: 0.96, alpha: 0.18)
            material.emission.contents = UIColor(red: 0.44, green: 0.92, blue: 0.96, alpha: 0.32)
            return material
        }

        private func uiColor(for zone: BodyZone) -> UIColor {
            switch zone {
            case .heart:
                UIColor(red: 1.00, green: 0.24, blue: 0.36, alpha: 1)
            case .chest, .back, .shoulders, .biceps, .triceps:
                UIColor(red: 0.55, green: 0.62, blue: 1.00, alpha: 1)
            case .core:
                UIColor(red: 1.00, green: 0.70, blue: 0.26, alpha: 1)
            case .glutes, .quads, .hamstrings, .calves:
                UIColor(red: 0.24, green: 0.86, blue: 0.72, alpha: 1)
            }
        }

        private func clamp<T: Comparable>(_ value: T, min minimum: T, max maximum: T) -> T {
            Swift.min(Swift.max(value, minimum), maximum)
        }
    }
}

#Preview {
    ScrollView {
        FitnessBodyMapSection(
            analysis: BodyMapAnalyzer.analyze(
                activities: [
                    WeeklyActivity(
                        id: "preview-run",
                        workoutUUID: nil,
                        workoutType: "Running",
                        displayName: "Running",
                        category: .running,
                        startDate: .now,
                        endDate: .now.addingTimeInterval(2_700),
                        duration: 2_700,
                        calories: 340,
                        distanceMeters: 6_200,
                        averageHeartRate: 142,
                        maxHeartRate: 171,
                        source: .healthKit,
                        sourceName: "Preview"
                    )
                ]
            )
        )
        .padding(18)
    }
    .background(FitnessWeeklyBackground())
}
