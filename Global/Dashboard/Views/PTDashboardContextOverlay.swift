//
//  PTDashboardContextOverlay.swift
//  CrazyDashboard
//
//  EN: Low-interruption overlay for navigation, warnings and degraded links.
//  ES: Superposición de baja interrupción para navegación, avisos y enlaces degradados.
//  中文：用于导航、警告和连接降级状态的低干扰覆盖层。
//

import UIKit

@MainActor
final class PTDashboardContextOverlay: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 12
        clipsToBounds = true
        isHidden = true
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        detailLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 2
        addSubview(iconView)
        addSubview(labels)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PTDashboardContextOverlay does not support storyboard construction")
    }

    func render(_ snapshot: PTDashboardContextSnapshot) {
        let context = snapshot.primaryContext
        guard context != .parked else {
            isHidden = true
            return
        }

        let content: (String, String, String, UIColor)
        switch context {
        case .maneuver:
            let distance = snapshot.navigationDistanceMeters.map { String(format: "%.0f m", $0) } ?? "--"
            let road = snapshot.navigationRoadName?.isEmpty == false ? snapshot.navigationRoadName! : "--"
            content = (
                "dashboard_context_maneuver",
                "\(distance) · \(road)",
                "arrow.triangle.turn.up.right.diamond.fill",
                .systemBlue
            )
        case .navigating:
            let road = snapshot.navigationRoadName?.isEmpty == false ? snapshot.navigationRoadName! : "--"
            content = ("dashboard_context_navigation", road, "location.north.line.fill", .systemBlue)
        case .warning:
            content = ("dashboard_context_warning", "", "exclamationmark.triangle.fill", .systemRed)
        case .connectionDegraded:
            content = ("dashboard_context_connection_degraded", "", "antenna.radiowaves.left.and.right.slash", .systemOrange)
        case .mediaChanged:
            content = ("dashboard_context_media_changed", "", "music.note", .systemPurple)
        case .riding:
            content = ("dashboard_context_riding", "", "motorcycle.fill", .systemGreen)
        case .parked:
            isHidden = true
            return
        }

        iconView.image = UIImage(systemName: content.2)
        iconView.tintColor = content.3
        titleLabel.text = PTDashboardConfig.languageFunc(text: content.0)
        detailLabel.text = content.1
        accessibilityLabel = [titleLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
        isHidden = false
    }
}

// EN: Both Twin renderers consume the same module contract without opening a transport path.
// ES: Ambos renderizadores Twin consumen el mismo contrato de módulo sin abrir un transporte.
// 中文：2D 与 3D Twin 渲染器都消费同一个模块契约，不会开启新的传输路径。
@MainActor
extension PTXP400TwinView: PTDashboardModuleView {
    var dashboardModule: PTDashboardModule { .vehicleTwin }

    func applyDashboardPresentation(_ presentation: PTDashboardModulePresentation) {
        isHidden = !presentation.isVisible
        alpha = presentation.isEmphasized ? 1 : 0.98
        let scale: CGFloat = presentation.isCompact ? 0.94 : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

@MainActor
extension PTXP400Twin3DView: PTDashboardModuleView {
    var dashboardModule: PTDashboardModule { .vehicleTwin }

    func applyDashboardPresentation(_ presentation: PTDashboardModulePresentation) {
        isHidden = !presentation.isVisible
        alpha = presentation.isEmphasized ? 1 : 0.98
        let scale: CGFloat = presentation.isCompact ? 0.94 : 1
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}
