//
//  PTVehicleTwin3DView.swift
//  CrazyDashboard
//
//  EN: Read-only SceneKit renderer driven exclusively by PTVehicleTwinSnapshot.
//  ES: Renderizador SceneKit de solo lectura impulsado exclusivamente por PTVehicleTwinSnapshot.
//  中文：只读 SceneKit 渲染器，只接收 PTVehicleTwinSnapshot，不直接监听车辆传输层。
//

import SceneKit
import UIKit
import PooTools
import SnapKit

@MainActor
final class PTXP400Twin3DView: UIView {
    private let sceneView = SCNView(frame: .zero)
    private let speedLabel = UILabel()
    private let fuelLabel = UILabel()
    private let voltageLabel = UILabel()
    private let stateLabel = UILabel()
    private let rpmProgress = UIProgressView(progressViewStyle: .bar)
    private let overlay = UIStackView()

    private var configuration = PTVehicleTwinConfiguration.xp400
    private var nodeReferences: PTVehicleTwin3DNodeReferences?
    private var cameraNode: SCNNode?
    private var ambientLight: SCNLight?
    private var currentSnapshot = PTVehicleTwinSnapshot.empty
    private var lastSnapshotDate: Date?
    private var wheelRotation: Float = 0
    private(set) var cameraPreset: PTVehicleTwin3DCameraPreset = .follow
    private(set) var fallbackReason: PTVehicleTwin3DFallbackReason?
    private(set) var isRendererAvailable = false

    var onFallbackSuggested: ((PTVehicleTwin3DFallbackReason) -> Void)?

    var shouldFallbackTo2D: Bool {
        !isRendererAvailable || fallbackReason != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        configure(.xp400)
    }

    required init?(coder: NSCoder) {
        fatalError("PTXP400Twin3DView does not support storyboard construction")
    }

    func configure(_ configuration: PTVehicleTwinConfiguration) {
        // EN: Build 76 pins the active 3D renderer to the verified XP400 material set.
        // ES: Build 76 fija el renderizador 3D activo al conjunto de recursos XP400 verificado.
        // 中文：Build 76 将当前 3D 渲染器固定到已验证的 XP400 素材集。
        let activeConfiguration: PTVehicleTwinConfiguration
        switch configuration.model {
        case .xp400, .xp400GT:
            activeConfiguration = .xp400
        }
        self.configuration = activeConfiguration
        let asset = PTVehicleTwin3DAssetFactory.makeScene(configuration: activeConfiguration)
        sceneView.scene = asset.scene
        nodeReferences = asset.nodes
        cameraNode = makeCamera(in: asset.scene)
        isRendererAvailable = cameraNode != nil && nodeReferences != nil
        fallbackReason = isRendererAvailable ? nil : .rendererUnavailable
        setCameraPreset(.follow, animated: false)
        update(snapshot: currentSnapshot, animated: false)
    }

    func update(snapshot: PTVehicleTwinSnapshot, animated: Bool = true) {
        currentSnapshot = snapshot
        refreshFallbackState()

        guard isRendererAvailable, let nodeReferences else { return }

        let duration: CFTimeInterval = UIAccessibility.isReduceMotionEnabled || !animated ? 0 : 0.12
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        updateWheelRotation(snapshot: snapshot)
        updateMotion(snapshot: snapshot, nodes: nodeReferences)
        updateLights(snapshot: snapshot, nodes: nodeReferences)
        updateState(snapshot: snapshot, nodes: nodeReferences)
        updateCameraPolicy(snapshot: snapshot)
        SCNTransaction.commit()
        sceneView.setNeedsDisplay()
    }

    func refreshFallbackState() {
        let nextFallback = PTVehicleTwin3DPerformancePolicy.fallbackReason(
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        if let nextFallback {
            if fallbackReason != nextFallback {
                fallbackReason = nextFallback
                onFallbackSuggested?(nextFallback)
            }
        } else if isRendererAvailable {
            fallbackReason = nil
        }
    }

    func setCameraPreset(_ preset: PTVehicleTwin3DCameraPreset, animated: Bool = true) {
        cameraPreset = preset
        guard let cameraNode else { return }
        let position: SCNVector3
        switch preset {
        case .front:
            position = SCNVector3(3.35, 1.20, 0)
        case .rear:
            position = SCNVector3(-3.35, 1.20, 0)
        case .left:
            position = SCNVector3(0, 1.20, 3.35)
        case .right:
            position = SCNVector3(0, 1.20, -3.35)
        case .top:
            position = SCNVector3(0, 4.1, 0.01)
        case .follow:
            position = SCNVector3(3.0, 1.35, 2.45)
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled || !animated ? 0 : 0.20
        cameraNode.position = position
        cameraNode.look(at: SCNVector3(0, 0.75, 0))
        SCNTransaction.commit()
        sceneView.setNeedsDisplay()
    }

    func reset() {
        update(snapshot: .empty, animated: false)
    }

    // EN: Theme only changes the SceneKit backdrop, ambient tint and info-card decoration.
    // ES: El tema solo cambia el fondo de SceneKit, el tinte ambiental y la decoración de la tarjeta.
    // 中文：主题只改变 SceneKit 背景、环境光色调和信息卡装饰。
    func applyDashboardTheme(_ tokens: PTDashboardThemeTokens) {
        let opacity = CGFloat(tokens.decorationOpacity)
        backgroundColor = tokens.backgroundColor
        sceneView.backgroundColor = tokens.backgroundColor
        ambientLight?.color = tokens.ambientColor
        ambientLight?.intensity = 720 * max(0.55, Double(opacity))
        overlay.backgroundColor = tokens.cardStartColor.withAlphaComponent(0.72 * max(0.35, opacity))
        overlay.layer.borderColor = tokens.glowColor.withAlphaComponent(0.42).cgColor
        overlay.layer.borderWidth = 1
    }

    private func configureView() {
        backgroundColor = UIColor(white: 0.05, alpha: 1)
        layer.cornerRadius = 18
        layer.masksToBounds = true

        sceneView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        sceneView.preferredFramesPerSecond = PTVehicleTwin3DPerformancePolicy.preferredFramesPerSecond
        sceneView.antialiasingMode = .none
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.rendersContinuously = false
        addSubview(sceneView)
        sceneView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureOverlayLabel(speedLabel)
        configureOverlayLabel(fuelLabel)
        configureOverlayLabel(voltageLabel)
        configureOverlayLabel(stateLabel)
        stateLabel.numberOfLines = 2
        rpmProgress.progressTintColor = .systemGreen
        rpmProgress.trackTintColor = UIColor.white.withAlphaComponent(0.16)
        rpmProgress.progress = 0

        overlay.axis = .vertical
        overlay.spacing = 4
        overlay.alignment = .fill
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        overlay.isLayoutMarginsRelativeArrangement = true
        overlay.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        overlay.layer.cornerRadius = 12
        overlay.addArrangedSubview(speedLabel)
        overlay.addArrangedSubview(fuelLabel)
        overlay.addArrangedSubview(voltageLabel)
        overlay.addArrangedSubview(rpmProgress)
        overlay.addArrangedSubview(stateLabel)
        addSubview(overlay)
        overlay.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(10)
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.62)
        }
        isAccessibilityElement = false
    }

    private func configureOverlayLabel(_ label: UILabel) {
        label.textColor = .white
        label.font = .appfont(size: 11, bold: true)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
    }

    private func makeCamera(in scene: SCNScene) -> SCNNode? {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 48
        camera.zNear = 0.05
        camera.zFar = 50
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.52, alpha: 1)
        ambient.intensity = 720
        ambientLight = ambient
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        let key = SCNLight()
        key.type = .omni
        key.color = UIColor(white: 0.90, alpha: 1)
        key.intensity = 980
        keyNode.light = key
        keyNode.position = SCNVector3(2.2, 4.0, 3.0)
        scene.rootNode.addChildNode(keyNode)
        return cameraNode
    }

    private func updateWheelRotation(snapshot: PTVehicleTwinSnapshot) {
        guard let speed = snapshot.speedKmh,
              speed.freshness == .fresh || speed.freshness == .aging,
              speed.value.isFinite else {
            lastSnapshotDate = snapshot.updatedAt
            return
        }

        let currentDate = snapshot.updatedAt
        let delta = lastSnapshotDate.map { currentDate.timeIntervalSince($0) } ?? 0.05
        let clampedDelta = min(max(delta, 0.0), 0.25)
        let wheelRadius = 0.34
        let distanceMeters = max(0, speed.value) / 3.6 * clampedDelta
        wheelRotation += Float(distanceMeters / (2 * Double.pi * wheelRadius) * 2 * Double.pi)
        lastSnapshotDate = currentDate

        guard let nodes = nodeReferences else { return }
        nodes.frontWheel.eulerAngles.z = wheelRotation
        nodes.rearWheel.eulerAngles.z = wheelRotation
    }

    private func updateMotion(snapshot: PTVehicleTwinSnapshot, nodes: PTVehicleTwin3DNodeReferences) {
        let lean = Float(max(-22, min(22, snapshot.leanDegrees?.value ?? 0))) * .pi / 180
        let pitch = Float(max(-10, min(10, snapshot.pitchDegrees?.value ?? 0))) * .pi / 180
        nodes.root.eulerAngles = SCNVector3(pitch, 0, -lean)

        let lateralG = Float(max(-1.5, min(1.5, snapshot.lateralG?.value ?? 0)))
        let longitudinalG = Float(max(-1.5, min(1.5, snapshot.longitudinalG?.value ?? 0)))
        nodes.gVector.eulerAngles = SCNVector3(-longitudinalG * 0.22, 0, -lateralG * 0.22)
        nodes.gVector.opacity = snapshot.lateralG == nil && snapshot.longitudinalG == nil
            ? 0.12
            : CGFloat(opacity(for: snapshot.freshness))
    }

    private func updateLights(snapshot: PTVehicleTwinSnapshot, nodes: PTVehicleTwin3DNodeReferences) {
        let headlightOn = snapshot.highBeamOn?.value == true || snapshot.lowBeamOn?.value == true
        updateLamp(nodes.headlight, isOn: headlightOn, color: .systemYellow, snapshot: snapshot)
        updateLamp(nodes.indicatorLeft, isOn: snapshot.leftIndicatorOn?.value == true || snapshot.hazardOn?.value == true, color: .systemOrange, snapshot: snapshot)
        updateLamp(nodes.indicatorRight, isOn: snapshot.rightIndicatorOn?.value == true || snapshot.hazardOn?.value == true, color: .systemOrange, snapshot: snapshot)

        // EN: Brake state is intentionally not inferred because the shared snapshot has no reliable brake signal.
        // ES: El estado del freno no se infiere porque la instantánea compartida no tiene una señal fiable de freno.
        // 中文：共享快照没有可靠刹车信号，因此这里不会臆测刹车灯状态。
        updateLamp(nodes.brakeLight, isOn: false, color: .systemRed, snapshot: snapshot)
    }

    private func updateLamp(_ node: SCNNode, isOn: Bool, color: UIColor, snapshot: PTVehicleTwinSnapshot) {
        node.opacity = isOn ? CGFloat(opacity(for: snapshot.freshness)) : 0.22
        guard let material = node.geometry?.firstMaterial else { return }
        material.emission.contents = isOn ? color : UIColor.clear
        material.diffuse.contents = isOn ? color : color.withAlphaComponent(0.32)
    }

    private func updateState(snapshot: PTVehicleTwinSnapshot, nodes: PTVehicleTwin3DNodeReferences) {
        let rpm = snapshot.rpm?.value ?? 0
        let rpmRatio = Float(max(0, min(1, rpm / 12_000)))
        rpmProgress.setProgress(rpmRatio, animated: !UIAccessibility.isReduceMotionEnabled)
        nodes.rpmIndicator.opacity = CGFloat(0.24 + (0.76 * rpmRatio)) * CGFloat(opacity(for: snapshot.freshness))

        let kickstandDown = snapshot.kickstandDown?.value == true
        nodes.kickstand.eulerAngles.z = kickstandDown ? -0.35 : -0.04
        nodes.kickstand.opacity = snapshot.kickstandDown == nil ? 0.22 : CGFloat(opacity(for: snapshot.freshness))

        speedLabel.text = metricText(snapshot.speedKmh) { value in
            String(format: "%.1f %@", PTDashboardConfig.shared.appShowMileage(value), PTDashboardConfig.shared.appShowUniLabel)
        }
        fuelLabel.text = metricText(snapshot.fuelPercent) { value in
            String(format: "%.0f%%", value)
        }
        voltageLabel.text = metricText(snapshot.voltage) { value in
            String(format: "%.2f V", value)
        }
        stateLabel.text = [
            stateText(snapshot.engineState?.value.rawValue),
            "TCS \(stateText(snapshot.tcsState?.value.rawValue))",
            "ABS \(stateText(snapshot.absState?.value.rawValue))"
        ].joined(separator: " · ")
        overlay.alpha = CGFloat(opacity(for: snapshot.freshness))
    }

    private func updateCameraPolicy(snapshot: PTVehicleTwinSnapshot) {
        let isMoving = snapshot.speedKmh.map {
            ($0.freshness == .fresh || $0.freshness == .aging) && $0.value > 1
        } ?? false
        if isMoving && cameraPreset != .follow {
            setCameraPreset(.follow, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        sceneView.allowsCameraControl = !isMoving
        sceneView.cameraControlConfiguration.allowsTranslation = false
    }

    private func metricText<Value>(_ metric: PTVehicleTwinMetric<Value>?, transform: (Value) -> String) -> String {
        guard let metric, metric.freshness != .unavailable else { return "--" }
        let prefix: String
        switch metric.freshness {
        case .fresh:
            prefix = ""
        case .aging:
            prefix = "~"
        case .stale:
            prefix = "? "
        case .unavailable:
            prefix = ""
        }
        return prefix + transform(metric.value)
    }

    private func stateText(_ rawValue: String?) -> String {
        guard let rawValue else { return "--" }
        return PTDashboardConfig.languageFunc(text: rawValue)
    }

    private func opacity(for freshness: PTVehicleTwinFreshness) -> Float {
        switch freshness {
        case .fresh:
            return 1
        case .aging:
            return 0.86
        case .stale:
            return 0.58
        case .unavailable:
            return 0.34
        }
    }
}
