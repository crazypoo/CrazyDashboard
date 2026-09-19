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
    private let headlightLayer = CAShapeLayer()
    private let leftIndicatorLayer = CAShapeLayer()
    private let rightIndicatorLayer = CAShapeLayer()
    private let kickstandLayer = CAShapeLayer()

    private var currentSnapshot = PTVehicleTwinSnapshot.empty
    private var wheelRotation: CGFloat = 0
    private var configuration = PTVehicleTwinConfiguration.xp400GT

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(shadowLayer)
        layer.addSublayer(bodyLayer)
        layer.addSublayer(accentLayer)
        layer.addSublayer(rearWheelLayer)
        layer.addSublayer(frontWheelLayer)
        layer.addSublayer(headlightLayer)
        layer.addSublayer(leftIndicatorLayer)
        layer.addSublayer(rightIndicatorLayer)
        layer.addSublayer(kickstandLayer)
        configureLayerDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("PTXP400TwinView does not support storyboard construction")
    }

    func configure(_ configuration: PTVehicleTwinConfiguration) {
        self.configuration = configuration
        setNeedsLayout()
    }

    func update(snapshot: PTVehicleTwinSnapshot, animated: Bool = true) {
        currentSnapshot = snapshot
        if let speed = snapshot.speedKmh?.value, speed.isFinite {
            wheelRotation += CGFloat(speed / 180.0)
        }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        drawVehicle()
        renderCurrentSnapshot()
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
        headlightLayer.fillColor = UIColor.systemYellow.cgColor
        leftIndicatorLayer.fillColor = UIColor.systemOrange.cgColor
        rightIndicatorLayer.fillColor = UIColor.systemOrange.cgColor
        kickstandLayer.fillColor = UIColor(white: 0.55, alpha: 1).cgColor
        kickstandLayer.strokeColor = UIColor(white: 0.8, alpha: 1).cgColor
        kickstandLayer.lineWidth = 3
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
        rearWheelLayer.path = wheelPath(center: rearCenter, radius: wheelRadius)
        frontWheelLayer.path = wheelPath(center: frontCenter, radius: wheelRadius)

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

    private func wheelPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = UIBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + radius * 0.82, y: center.y))
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius * 0.82))
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x - radius * 0.58, y: center.y + radius * 0.58))
        return path.cgPath
    }

    private func renderCurrentSnapshot() {
        let lean = CGFloat(max(-22, min(22, currentSnapshot.leanDegrees?.value ?? 0))) * .pi / 180
        let pitch = CGFloat(max(-10, min(10, currentSnapshot.pitchDegrees?.value ?? 0)))
        let bodyTransform = CGAffineTransform(rotationAngle: lean).translatedBy(x: 0, y: -pitch)
        bodyLayer.setAffineTransform(bodyTransform)
        accentLayer.setAffineTransform(bodyTransform)
        kickstandLayer.setAffineTransform(bodyTransform)
        rearWheelLayer.setAffineTransform(CGAffineTransform(rotationAngle: wheelRotation))
        frontWheelLayer.setAffineTransform(CGAffineTransform(rotationAngle: wheelRotation))

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

        let headlightOn = currentSnapshot.highBeamOn?.value == true || currentSnapshot.lowBeamOn?.value == true
        headlightLayer.opacity = headlightOn ? 1 : 0.22
        leftIndicatorLayer.opacity = currentSnapshot.leftIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? 1 : 0.18
        rightIndicatorLayer.opacity = currentSnapshot.rightIndicatorOn?.value == true || currentSnapshot.hazardOn?.value == true ? 1 : 0.18
        kickstandLayer.isHidden = !configuration.supportsKickstand || currentSnapshot.kickstandDown?.value != true
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
        header.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview().inset(12)
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
