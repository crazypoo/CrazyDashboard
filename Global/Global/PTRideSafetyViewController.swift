//
//  PTRideSafetyViewController.swift
//  CrazyDashboard
//
//  EN: Read-only security history and controlled fleet point sharing for riders.
//  ES: Historial de seguridad de solo lectura y compartición controlada de puntos para pilotos.
//  中文：面向骑手的只读安全历史和受控车队点位分享页面。
//

import CoreLocation
import UIKit
import PooTools

@MainActor
final class PTRideSafetyViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    lazy var export : PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.titleLabel?.font = .appfont(size: 14)
        view.setTitle(PTDashboardConfig.languageFunc(text: "safety_export"), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: view.sizeFor().width + 5, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.exportAction()
        })
        return view
    }()
        
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "ride_safety_center")
        view.backgroundColor = .black
        configureLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [export])
        reloadContent()
    }

    private func configureLayout() {
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // EN: Rebuilding a small bounded stack keeps the safety screen deterministic and easy to audit.
    // ES: Reconstruir una pila pequeña y limitada mantiene la pantalla determinista y fácil de auditar.
    // 中文：重建一个有界的小型栈，让安全页面保持确定且易于审计。
    private func reloadContent() {
        PTSecurityEventTimelineStore.shared.purgeExpired()
        PTRideSharedPointStore.shared.purgeExpired()
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let events = PTSecurityEventTimelineStore.shared.events
        let eventLines = events.prefix(20).map { event in
            let date = DateFormatter.localizedString(
                from: event.timestamp,
                dateStyle: .short,
                timeStyle: .short
            )
            let coordinate = event.coordinate.map {
                String(format: " (%.4f, %.4f)", $0.latitude, $0.longitude)
            } ?? ""
            let acknowledgement = event.isAcknowledged
                ? PTDashboardConfig.languageFunc(text: "safety_acknowledged")
                : ""
            return "[\(date)] \(event.message)\(coordinate) \(acknowledgement)"
        }
        var timelineButtons: [UIButton] = []
        if let latestEvent = events.first, !latestEvent.isAcknowledged {
            let acknowledgeButton = makeButton(
                title: PTDashboardConfig.languageFunc(text: "safety_acknowledge_latest"),
                color: .systemOrange
            ) { [weak self] in
                _ = PTSecurityEventTimelineStore.shared.acknowledge(id: latestEvent.id)
                self?.reloadContent()
            }
            timelineButtons.append(acknowledgeButton)
        }
        let clearButton = makeButton(
            title: PTDashboardConfig.languageFunc(text: "safety_clear_timeline"),
            color: .systemRed
        ) { [weak self] in
            self?.confirmClearTimeline()
        }
        timelineButtons.append(clearButton)
        stackView.addArrangedSubview(makeCard(
            title: PTDashboardConfig.languageFunc(text: "safety_timeline"),
            body: eventLines.isEmpty
                ? PTDashboardConfig.languageFunc(text: "safety_no_events")
                : eventLines.joined(separator: "\n"),
            buttons: timelineButtons
        ))

        let points = PTRideSharedPointStore.shared.points
        let pointLines = points.prefix(20).map { point in
            let coordinate = String(format: "%.4f, %.4f", point.coordinate.latitude, point.coordinate.longitude)
            return "\(point.title) · \(coordinate)\n\(point.address.isEmpty ? point.note : point.address)"
        }
        let shareParkingButton = makeButton(
            title: PTDashboardConfig.languageFunc(text: "safety_share_parking"),
            color: PTDashboardConfig.shared.appMainColor
        ) { [weak self] in
            guard PTRideSharedPointStore.shared.shareParking() else {
                self?.showMessage(PTDashboardConfig.languageFunc(text: "safety_share_unavailable"))
                return
            }
            self?.reloadContent()
        }
        let shareHazardButton = makeButton(
            title: PTDashboardConfig.languageFunc(text: "safety_share_hazard"),
            color: .systemOrange
        ) { [weak self] in
            self?.presentHazardChoices()
        }
        stackView.addArrangedSubview(makeCard(
            title: PTDashboardConfig.languageFunc(text: "safety_fleet_points"),
            body: pointLines.isEmpty
                ? PTDashboardConfig.languageFunc(text: "safety_no_points")
                : pointLines.joined(separator: "\n\n"),
            buttons: [shareParkingButton, shareHazardButton]
        ))

        for point in points.prefix(20) {
            let removeButton = makeButton(
                title: PTDashboardConfig.languageFunc(text: "safety_remove_point"),
                color: .systemRed
            ) { [weak self] in
                _ = PTRideSharedPointStore.shared.remove(id: point.id)
                self?.reloadContent()
            }
            stackView.addArrangedSubview(makeCard(
                title: point.title,
                body: point.note.isEmpty
                    ? String(format: "%.5f, %.5f", point.coordinate.latitude, point.coordinate.longitude)
                    : point.note,
                buttons: [removeButton]
            ))
        }
    }

    private func makeCard(title: String, body: String, buttons: [UIButton]) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.1, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.35).cgColor

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        content.addArrangedSubview(titleLabel)

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.textColor = .white
        bodyLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        bodyLabel.numberOfLines = 0
        content.addArrangedSubview(bodyLabel)

        buttons.forEach { content.addArrangedSubview($0) }
        return card
    }

    private func makeButton(title: String, color: UIColor, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.8)
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func presentHazardChoices() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "safety_share_hazard"),
            message: PTDashboardConfig.languageFunc(text: "safety_share_hazard_hint"),
            preferredStyle: .actionSheet
        )
        let choices: [(PTRideSharedPointKind, String)] = [
            (.roadblock, "safety_hazard_roadblock"),
            (.slippery, "safety_hazard_slippery"),
            (.construction, "safety_hazard_construction"),
            (.fuel, "safety_hazard_fuel"),
            (.meeting, "safety_hazard_meeting")
        ]
        choices.forEach { kind, key in
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: key),
                style: .default
            ) { [weak self] _ in
                let title = PTDashboardConfig.languageFunc(text: key)
                guard PTRideSharedPointStore.shared.shareHazard(kind: kind, title: title) else {
                    self?.showMessage(PTDashboardConfig.languageFunc(text: "safety_share_unavailable"))
                    return
                }
                self?.reloadContent()
            })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmClearTimeline() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "safety_clear_timeline"),
            message: PTDashboardConfig.languageFunc(text: "safety_clear_timeline_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "safety_clear_timeline"),
            style: .destructive
        ) { [weak self] _ in
            PTSecurityEventTimelineStore.shared.clear()
            self?.reloadContent()
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        present(alert, animated: true)
    }

    @objc private func exportAction() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "safety_export"),
            message: PTDashboardConfig.languageFunc(text: "safety_export_hint"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "safety_export_timeline"),
            style: .default
        ) { [weak self] _ in
            self?.shareExport { try PTSecurityEventTimelineStore.shared.exportURL(format: .json) }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "safety_export_points"),
            style: .default
        ) { [weak self] _ in
            self?.shareExport { try PTRideSharedPointStore.shared.exportURL(format: .json) }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "safety_export_csv"),
            style: .default
        ) { [weak self] _ in
            self?.shareExport { try PTSecurityEventTimelineStore.shared.exportURL(format: .csv) }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func shareExport(_ makeURL: () throws -> URL) {
        do {
            let activity = UIActivityViewController(activityItems: [try makeURL()], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: PTDashboardConfig.languageFunc(text: "alert_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
        present(alert, animated: true)
    }
}
