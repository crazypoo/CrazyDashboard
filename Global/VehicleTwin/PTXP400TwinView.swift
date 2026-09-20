//
//  PTXP400TwinView.swift
//  CrazyDashboard
//
//  EN: Lightweight UIKit 2D renderer for the XP400 Digital Twin.
//  ES: Renderizador UIKit 2D ligero para el Digital Twin de XP400.
//  中文：XP400 数字孪生的轻量 UIKit 2D 渲染器。
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTXP400TwinView: UIView {
    private let shadowLayer = CAShapeLayer()
    private let bodyLayer = CAShapeLayer()
    private let accentLayer = CAShapeLayer()
    private let frontWheelLayer = CAShapeLayer()
    private let rearWheelLayer = CAShapeLayer()
    private let frontWheelSpokesLayer = CAShapeLayer()
    private let rearWheelSpokesLayer = CAShapeLayer()
    private let headlightLayer = CAShapeLayer()
    private let leftIndicatorLayer = CAShapeLayer()
    private let rightIndicatorLayer = CAShapeLayer()
    private let kickstandLayer = CAShapeLayer()

    private let xp400ShadowImageView = UIImageView()
    private let xp400AssetContainer = UIView()
    private let xp400BodyImageView = UIImageView()
    private let xp400FrontWheelBaseImageView = UIImageView()
    private let xp400FrontWheelSpokesImageView = UIImageView()
    private let xp400RearWheelBaseImageView = UIImageView()
    private let xp400RearWheelSpokesImageView = UIImageView()
    private let xp400WindshieldImageView = UIImageView()
    private let xp400HeadlightImageView = UIImageView()
    private let xp400BrakeLightImageView = UIImageView()
    private let xp400LeftIndicatorImageView = UIImageView()
    private let xp400RightIndicatorImageView = UIImageView()
    private let xp400KickstandImageView = UIImageView()

    private var currentSnapshot = PTVehicleTwinSnapshot.empty
    private var wheelRotation: CGFloat = 0
    private var lastSnapshotDate: Date?
    private var configuration = PTVehicleTwinConfiguration.xp400
    private var usesXP400Assets = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(shadowLayer)
        layer.addSublayer(bodyLayer)
        layer.addSublayer(accentLayer)
        layer.addSublayer(rearWheelLayer)
        layer.addSublayer(frontWheelLayer)
        layer.addSublayer(rearWheelSpokesLayer)
        layer.addSublayer(frontWheelSpokesLayer)
        layer.addSublayer(headlightLayer)
        layer.addSublayer(leftIndicatorLayer)
        layer.addSublayer(rightIndicatorLayer)
        layer.addSublayer(kickstandLayer)
        configureLayerDefaults()
        configureXP400AssetViews()
        loadXP400Assets()
    }

    required init?(coder: NSCoder) {
        fatalError("PTXP400TwinView does not support storyboard construction")
    }

    func configure(_ configuration: PTVehicleTwinConfiguration) {
        // EN: Build 76 uses the verified XP400 asset set for both 2D and 3D surfaces.
        // ES: Build 76 usa el conjunto de recursos XP400 verificado para las superficies 2D y 3D.
        // 中文：Build 76 的 2D 和 3D 页面统一使用已验证的 XP400 素材集。
        self.configuration = configuration.model == .xp400 ? configuration : .xp400
        loadXP400Assets()
        setNeedsLayout()
    }

    // EN: Theme application is decorative and never recolors semantic vehicle indicators.
    // ES: La aplicación del tema es decorativa y nunca recolorea indicadores semánticos del vehículo.
    // 中文：主题应用只负责装饰，不会重绘车辆语义指示器。
    func applyDashboardTheme(_ tokens: PTDashboardThemeTokens) {
        backgroundColor = tokens.backgroundColor.withAlphaComponent(0.88)
        shadowLayer.fillColor = tokens.ambientColor.withAlphaComponent(0.28).cgColor
        layer.shadowColor = tokens.glowColor.cgColor
        layer.shadowOpacity = Float(min(0.34, 0.22 * tokens.decorationOpacity))
        layer.shadowRadius = 14
        layer.shadowOffset = .zero
    }

    func update(snapshot: PTVehicleTwinSnapshot, animated: Bool = true) {
        currentSnapshot = snapshot
        updateWheelRotation(snapshot: snapshot)
        if animated {
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) { [weak self] in
                self?.renderCurrentSnapshot()
            }
        } else {
            renderCurrentSnapshot()
        }
    }

    private func configureLayerDefaults() {
        shadowLayer.fillColor = UIColor.black.withAlphaComponent(0.35).cgColor
        bodyLayer.fillColor = UIColor(red: 0.10, green: 0.24, blue: 0.56, alpha: 1).cgColor
        bodyLayer.strokeColor = UIColor(red: 0.32, green: 0.62, blue: 1, alpha: 1).cgColor
        bodyLayer.lineWidth = 2
        accentLayer.fillColor = UIColor(red: 0.22, green: 0.43, blue: 0.88, alpha: 1).cgColor
        accentLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        accentLayer.lineWidth = 1
        [rearWheelLayer, frontWheelLayer].forEach {
            $0.fillColor = UIColor(white: 0.08, alpha: 1).cgColor
            $0.strokeColor = UIColor(white: 0.65, alpha: 1).cgColor
            $0.lineWidth = 3
        }
        [rearWheelSpokesLayer, frontWheelSpokesLayer].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.strokeColor = UIColor(white: 0.55, alpha: 1).cgColor
            $0.lineWidth = 2
            $0.lineCap = .round
        }
        headlightLayer.fillColor = UIColor.systemYellow.cgColor
        leftIndicatorLayer.fillColor = UIColor.systemOrange.cgColor
        rightIndicatorLayer.fillColor = UIColor.systemOrange.cgColor
        kickstandLayer.fillColor = UIColor(white: 0.55, alpha: 1).cgColor
        kickstandLayer.strokeColor = UIColor(white: 0.8, alpha: 1).cgColor
        kickstandLayer.lineWidth = 3
    }

    private func configureXP400AssetViews() {
        xp400ShadowImageView.contentMode = .scaleToFill
        xp400AssetContainer.backgroundColor = .clear
        xp400AssetContainer.isUserInteractionEnabled = false
        xp400AssetContainer.layer.anchorPoint = CGPoint(x: 0.50, y: 0.55)
        xp400AssetContainer.clipsToBounds = false

        addSubview(xp400ShadowImageView)
        addSubview(xp400AssetContainer)

        let imageViews = [
            xp400BodyImageView,
            xp400RearWheelBaseImageView,
            xp400RearWheelSpokesImageView,
            xp400FrontWheelBaseImageView,
            xp400FrontWheelSpokesImageView,
            xp400WindshieldImageView,
            xp400HeadlightImageView,
            xp400BrakeLightImageView,
            xp400LeftIndicatorImageView,
            xp400RightIndicatorImageView,
            xp400KickstandImageView
        ]
        imageViews.forEach { imageView in
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            xp400AssetContainer.addSubview(imageView)
        }
    }

    private func loadXP400Assets() {
        let names = [
            "body": xp400BodyImageView,
            "front_wheel_base": xp400FrontWheelBaseImageView,
            "front_wheel_spokes": xp400FrontWheelSpokesImageView,
            "rear_wheel_base": xp400RearWheelBaseImageView,
            "rear_wheel_spokes": xp400RearWheelSpokesImageView,
            "windshield": xp400WindshieldImageView,
            "headlight": xp400HeadlightImageView,
            "brake_light": xp400BrakeLightImageView,
            "indicator_left": xp400LeftIndicatorImageView,
            "indicator_right": xp400RightIndicatorImageView,
            "kickstand": xp400KickstandImageView
        ]
        let folder = "XP400Twin2DAssets/xp400"
        let loaded = names.allSatisfy { name, imageView in
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder),
                  let image = UIImage(contentsOfFile: url.path) else {
                return false
            }
            imageView.image = image
            return true
        }
        guard loaded else {
            usesXP400Assets = false
            setFallbackLayerVisibility()
            return
        }

        guard let shadowURL = Bundle.main.url(
            forResource: "shadow",
            withExtension: "png",
            subdirectory: folder
        ), let shadowImage = UIImage(contentsOfFile: shadowURL.path) else {
            usesXP400Assets = false
            setFallbackLayerVisibility()
            return
        }
        xp400ShadowImageView.image = shadowImage
        usesXP400Assets = true
        setFallbackLayerVisibility()
    }

    private func drawVehicle() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let width = bounds.width
        let height = bounds.height
        let wheelRadius = min(width * 0.105, height * 0.19)
        let rearCenter = CGPoint(x: width * 0.25, y: height * 0.70)
        let frontCenter = CGPoint(x: width * 0.76, y: height * 0.70)

        shadowLayer.path = UIBezierPath(
            ovalIn: CGRect(x: width * 0.12, y: height * 0.80, width: width * 0.76, height: height * 0.08)
        ).cgPath
        rearWheelLayer.path = wheelCirclePath(center: rearCenter, radius: wheelRadius)
        frontWheelLayer.path = wheelCirclePath(center: frontCenter, radius: wheelRadius)
        configureSpokesLayer(rearWheelSpokesLayer, center: rearCenter, radius: wheelRadius)
        configureSpokesLayer(frontWheelSpokesLayer, center: frontCenter, radius: wheelRadius)

        let body = UIBezierPath()
        body.move(to: CGPoint(x: width * 0.18, y: height * 0.62))
        body.addCurve(
            to: CGPoint(x: width * 0.43, y: height * 0.43),
            controlPoint1: CGPoint(x: width * 0.23, y: height * 0.43),
            controlPoint2: CGPoint(x: width * 0.31, y: height * 0.34)
        )
        body.addLine(to: CGPoint(x: width * 0.60, y: height * 0.45))
        body.addLine(to: CGPoint(x: width * 0.73, y: height * 0.61))
        body.addLine(to: CGPoint(x: width * 0.59, y: height * 0.66))
        body.addLine(to: CGPoint(x: width * 0.37, y: height * 0.64))
        body.addLine(to: CGPoint(x: width * 0.18, y: height * 0.62))
        body.close()
        bodyLayer.path = body.cgPath

        let accent = UIBezierPath()
        accent.move(to: CGPoint(x: width * 0.38, y: height * 0.48))
        accent.addLine(to: CGPoint(x: width * 0.58, y: height * 0.51))
        accent.addLine(to: CGPoint(x: width * 0.64, y: height * 0.60))
        accent.addLine(to: CGPoint(x: width * 0.43, y: height * 0.58))
        accent.close()
        accentLayer.path = accent.cgPath

        let headlight = UIBezierPath(
            ovalIn: CGRect(x: width * 0.71, y: height * 0.53, width: width * 0.055, height: height * 0.055)
        )
        headlightLayer.path = headlight.cgPath
        leftIndicatorLayer.path = UIBezierPath(
            ovalIn: CGRect(x: width * 0.66, y: height * 0.60, width: width * 0.035, height: height * 0.035)
        ).cgPath
        rightIndicatorLayer.path = UIBezierPath(
            ovalIn: CGRect(x: width * 0.79, y: height * 0.60, width: width * 0.035, height: height * 0.035)
        ).cgPath

        let kickstand = UIBezierPath()
        kickstand.move(to: CGPoint(x: width * 0.40, y: height * 0.63))
        kickstand.addLine(to: CGPoint(x: width * 0.33, y: height * 0.80))
        kickstand.addLine(to: CGPoint(x: width * 0.28, y: height * 0.80))
        kickstand.addLine(to: CGPoint(x: width * 0.37, y: height * 0.63))
        kickstand.close()
        kickstandLayer.path = kickstand.cgPath
    }

    private func wheelCirclePath(center: CGPoint, radius: CGFloat) -> CGPath {
        UIBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).cgPath
    }

    private func configureSpokesLayer(_ layer: CAShapeLayer, center: CGPoint, radius: CGFloat) {
        let diameter = radius * 2
        layer.bounds = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = center
        let localCenter = CGPoint(x: radius, y: radius)
        let path = UIBezierPath()
        path.move(to: localCenter)
        path.addLine(to: CGPoint(x: radius * 1.82, y: radius * 0.83))
        path.move(to: localCenter)
        path.addLine(to: CGPoint(x: radius * 0.53, y: radius * 0.30))
        path.move(to: localCenter)
        path.addLine(to: CGPoint(x: radius * 0.42, y: radius * 1.58))
        layer.path = path.cgPath
    }

    private func renderCurrentSnapshot() {
        let lean = CGFloat(max(-22, min(22, currentSnapshot.leanDegrees?.value ?? 0))) * .pi / 180
        let pitch = CGFloat(max(-10, min(10, currentSnapshot.pitchDegrees?.value ?? 0)))
        let bodyTransform = CGAffineTransform(rotationAngle: lean).translatedBy(x: 0, y: -pitch)
        bodyLayer.setAffineTransform(bodyTransform)
        accentLayer.setAffineTransform(bodyTransform)
        kickstandLayer.setAffineTransform(bodyTransform)
        rearWheelLayer.setAffineTransform(.identity)
        frontWheelLayer.setAffineTransform(.identity)
        rearWheelSpokesLayer.setAffineTransform(CGAffineTransform(rotationAngle: wheelRotation))
        frontWheelSpokesLayer.setAffineTransform(CGAffineTransform(rotationAngle: wheelRotation))

        let opacity: Float
        switch currentSnapshot.freshness {
        case .fresh:
            opacity = 1
        case .aging:
            opacity = 0.86
        case .stale:
            opacity = 0.58
        case .unavailable:
            opacity = 0.34
        }
        layer.opacity = opacity

        xp400AssetContainer.transform = usesXP400Assets ? bodyTransform : .identity
        xp400ShadowImageView.alpha = usesXP400Assets ? CGFloat(opacity * 0.72) : 0
        xp400FrontWheelSpokesImageView.transform = CGAffineTransform(rotationAngle: wheelRotation)
        xp400RearWheelSpokesImageView.transform = CGAffineTransform(rotationAngle: wheelRotation)
        xp400WindshieldImageView.alpha = CGFloat(opacity * 0.78)

        let headlightOn = currentSnapshot.highBeamOn?.value == true || currentSnapshot.lowBeamOn?.value == true
        headlightLayer.opacity = headlightOn ? 1 : 0.22
        leftIndicatorLayer.opacity = currentSnapshot.leftIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? 1 : 0.18
        rightIndicatorLayer.opacity = currentSnapshot.rightIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? 1 : 0.18
        kickstandLayer.isHidden = !configuration.supportsKickstand || currentSnapshot.kickstandDown?.value != true

        xp400HeadlightImageView.alpha = headlightOn ? CGFloat(opacity) : 0.22
        xp400LeftIndicatorImageView.alpha = currentSnapshot.leftIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? CGFloat(opacity) : 0.18
        xp400RightIndicatorImageView.alpha = currentSnapshot.rightIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? CGFloat(opacity) : 0.18
        xp400BrakeLightImageView.alpha = 0.18
        xp400KickstandImageView.alpha = currentSnapshot.kickstandDown?.value == true ? CGFloat(opacity) : 0.18
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let canvasFrame = xp400AssetCanvasFrame()
        xp400ShadowImageView.frame = canvasFrame
        xp400AssetContainer.bounds = CGRect(origin: .zero, size: canvasFrame.size)
        xp400AssetContainer.layer.position = CGPoint(
            x: canvasFrame.midX,
            y: canvasFrame.midY + canvasFrame.height * 0.05
        )

        let imageViews = [
            xp400BodyImageView,
            xp400RearWheelBaseImageView,
            xp400FrontWheelBaseImageView,
            xp400WindshieldImageView,
            xp400HeadlightImageView,
            xp400BrakeLightImageView,
            xp400LeftIndicatorImageView,
            xp400RightIndicatorImageView,
            xp400KickstandImageView
        ]
        imageViews.forEach { imageView in
            imageView.bounds = xp400AssetContainer.bounds
            imageView.center = CGPoint(
                x: xp400AssetContainer.bounds.midX,
                y: xp400AssetContainer.bounds.midY
            )
        }
        layoutXP400WheelImage(xp400RearWheelSpokesImageView, pivot: CGPoint(x: 0.25, y: 0.70))
        layoutXP400WheelImage(xp400FrontWheelSpokesImageView, pivot: CGPoint(x: 0.76, y: 0.70))
        drawVehicle()
        renderCurrentSnapshot()
    }

    // EN: Keep the XP400 full-canvas layers on their native 2:1 canvas so normalized wheel pivots stay exact.
    // ES: Mantiene las capas de lienzo completo de XP400 en su lienzo nativo 2:1 para conservar los pivotes exactos.
    // 中文：让 XP400 全画布分层保持原生 2:1 画布，确保归一化轮心始终准确。
    private func xp400AssetCanvasFrame() -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let aspectRatio: CGFloat = 2
        let canvasWidth = min(bounds.width, bounds.height * aspectRatio)
        let canvasHeight = canvasWidth / aspectRatio
        return CGRect(
            x: bounds.midX - canvasWidth * 0.5,
            y: bounds.midY - canvasHeight * 0.5,
            width: canvasWidth,
            height: canvasHeight
        )
    }

    private func layoutXP400WheelImage(_ imageView: UIImageView, pivot: CGPoint) {
        imageView.bounds = xp400AssetContainer.bounds
        imageView.layer.anchorPoint = pivot
        imageView.layer.position = CGPoint(
            x: xp400AssetContainer.bounds.width * pivot.x,
            y: xp400AssetContainer.bounds.height * pivot.y
        )
    }

    private func setFallbackLayerVisibility() {
        let hidden = usesXP400Assets
        [
            shadowLayer,
            bodyLayer,
            accentLayer,
            frontWheelLayer,
            rearWheelLayer,
            frontWheelSpokesLayer,
            rearWheelSpokesLayer,
            headlightLayer,
            leftIndicatorLayer,
            rightIndicatorLayer,
            kickstandLayer
        ].forEach { $0.isHidden = hidden }
        xp400ShadowImageView.isHidden = !usesXP400Assets
        xp400AssetContainer.isHidden = !usesXP400Assets
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
        let clampedDelta = min(max(delta, 0), 0.25)
        let radius = 0.34
        let wheelRevolutions = max(0, speed.value) / 3.6 * clampedDelta / (2 * Double.pi * radius)
        wheelRotation += CGFloat(wheelRevolutions * 2 * Double.pi)
        lastSnapshotDate = currentDate
    }
}

@MainActor
final class PTXP400TwinCardView: UIControl {
    private let twinView = PTXP400TwinView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let speedLabel = UILabel()
    private let rpmLabel = UILabel()
    private let fuelLabel = UILabel()
    private let voltageLabel = UILabel()
    private let tcsLabel = UILabel()
    private let absLabel = UILabel()
    private let openButton = UIButton(type: .system)

    var onOpen: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("PTXP400TwinCardView does not support storyboard construction")
    }

    func update(snapshot: PTVehicleTwinSnapshot) {
        twinView.update(snapshot: snapshot)
        titleLabel.text = PTDashboardConfig.languageFunc(text: "Vehicle Twin")
        let connection = snapshot.dashboardConnected
            ? PTDashboardConfig.languageFunc(text: "connect_success")
            : PTDashboardConfig.languageFunc(text: "ride_not_available")
        statusLabel.text = "\(connection) · \(freshnessText(snapshot.freshness))"
        speedLabel.text = metricText(snapshot.speedKmh, unit: PTDashboardConfig.shared.appShowUniLabel) { value in
            PTDashboardConfig.shared.appShowMileage(value)
        }
        rpmLabel.text = metricText(snapshot.rpm, unit: RPMUnit) { $0 }
        fuelLabel.text = metricText(snapshot.fuelPercent, unit: "%") { $0 }
        voltageLabel.text = metricText(snapshot.voltage, unit: "V") { $0 }
        tcsLabel.text = statusText(snapshot.tcsState?.value.rawValue)
        absLabel.text = statusText(snapshot.absState?.value.rawValue)
        accessibilityValue = [speedLabel.text, rpmLabel.text, fuelLabel.text, voltageLabel.text].compactMap { $0 }.joined(separator: " · ")
    }

    func reset() {
        update(snapshot: .empty)
    }

    func applyDashboardTheme(_ tokens: PTDashboardThemeTokens) {
        twinView.applyDashboardTheme(tokens)
        backgroundColor = tokens.cardStartColor.withAlphaComponent(0.78)
        titleLabel.textColor = tokens.primaryTextColor
        statusLabel.textColor = tokens.secondaryTextColor
        openButton.tintColor = tokens.glowColor
    }

    private func setupUI() {
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        layer.cornerRadius = 14
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = PTDashboardConfig.languageFunc(text: "Open")

        titleLabel.font = .appfont(size: 15, bold: true)
        titleLabel.textColor = .white
        statusLabel.font = .appfont(size: 11)
        statusLabel.textColor = .lightGray

        let header = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        header.axis = .vertical
        header.spacing = 2

        let metricStack = UIStackView(arrangedSubviews: [
            metricColumn(title: "Speed", label: speedLabel),
            metricColumn(title: "RPM", label: rpmLabel),
            metricColumn(title: "Fuel", label: fuelLabel),
            metricColumn(title: "Voltage", label: voltageLabel),
            metricColumn(title: "TCS", label: tcsLabel),
            metricColumn(title: "ABS", label: absLabel)
        ])
        metricStack.axis = .horizontal
        metricStack.distribution = .fillEqually
        metricStack.spacing = 4

        addSubview(header)
        addSubview(twinView)
        addSubview(metricStack)
        addSubview(openButton)
        twinView.isUserInteractionEnabled = false
        header.isUserInteractionEnabled = false
        metricStack.isUserInteractionEnabled = false

        openButton.setTitle(PTDashboardConfig.languageFunc(text: "Open"), for: .normal)
        openButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        openButton.semanticContentAttribute = .forceRightToLeft
        openButton.tintColor = PTDashboardConfig.shared.appMainColor
        openButton.titleLabel?.font = .appfont(size: 13, bold: true)
        openButton.accessibilityLabel = PTDashboardConfig.languageFunc(text: "Open")
        openButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        header.snp.makeConstraints { make in
            make.top.left.equalToSuperview().inset(12)
            make.right.equalTo(openButton.snp.left).offset(-8)
        }
        openButton.snp.makeConstraints { make in
            make.top.right.equalToSuperview().inset(8)
            make.height.equalTo(44)
            make.width.greaterThanOrEqualTo(64)
        }
        twinView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(10)
            make.top.equalTo(header.snp.bottom).offset(2)
            make.height.equalTo(108)
        }
        metricStack.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview().inset(10)
            make.top.equalTo(twinView.snp.bottom).offset(2)
            make.height.equalTo(32)
        }
    }

    private func metricColumn(title: String, label: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = PTDashboardConfig.languageFunc(text: title)
        titleLabel.textColor = .lightGray
        titleLabel.font = .appfont(size: 9)
        titleLabel.textAlignment = .center
        label.textColor = .white
        label.font = .appfont(size: 10, bold: true)
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [titleLabel, label])
        stack.axis = .vertical
        stack.spacing = 1
        return stack
    }

    private func metricText<Value>(_ metric: PTVehicleTwinMetric<Value>?, unit: String, transform: (Value) -> Double) -> String {
        guard let metric, metric.freshness != .unavailable else { return "--" }
        return "\(String(format: "%.0f", transform(metric.value)))\(unit)"
    }

    private func statusText(_ rawValue: String?) -> String {
        guard let rawValue else { return "--" }
        return PTDashboardConfig.languageFunc(text: rawValue)
    }

    private func freshnessText(_ freshness: PTVehicleTwinFreshness) -> String {
        switch freshness {
        case .fresh:
            return PTDashboardConfig.languageFunc(text: "Live")
        case .aging:
            return PTDashboardConfig.languageFunc(text: "Updating")
        case .stale:
            return PTDashboardConfig.languageFunc(text: "Stale")
        case .unavailable:
            return PTDashboardConfig.languageFunc(text: "Unavailable")
        }
    }

    @objc private func handleTap() {
        onOpen?()
    }
}
