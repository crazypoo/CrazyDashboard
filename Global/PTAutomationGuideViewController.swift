//
//  PTAutomationGuideViewController.swift
//  CrazyDashboard
//
//  EN: A read-only guide for the app's Siri, App Shortcuts, and URL Scheme capabilities.
//  ES: Guía de solo lectura para las capacidades de Siri, Atajos y URL Scheme de la app.
//  中文：用于介绍 App Siri、快捷指令和 URL Scheme 能力的只读页面。
//

import AppIntents
import SwiftUI
import UIKit
import PooTools
import SnapKit

// EN: Keep the guide catalog small and data-only so the page cannot execute a route by accident.
// ES: Mantén el catálogo pequeño y solo de datos para que la página no ejecute una ruta por accidente.
// 中文：保持目录小型且只包含数据，避免介绍页意外执行路由。
enum PTAutomationGuideCatalog {
    struct IntentItem: Equatable, Sendable {
        let id: String
        let titleKey: String
        let descriptionKey: String
        let contextKey: String
        let systemImageName: String
    }

    struct SchemeItem: Equatable, Sendable {
        let id: String
        let titleKey: String
        let descriptionKey: String
        let noteKey: String
        let examples: [String]
        let systemImageName: String
    }

    static let intentItems: [IntentItem] = [
        IntentItem(
            id: "vehicleStatus",
            titleKey: "app_intent_vehicle_status_title",
            descriptionKey: "app_intent_vehicle_status_description",
            contextKey: "automation_guide_intent_background",
            systemImageName: "motorcycle"
        ),
        IntentItem(
            id: "parkedLocation",
            titleKey: "app_intent_parked_location_title",
            descriptionKey: "app_intent_parked_location_description",
            contextKey: "automation_guide_intent_background",
            systemImageName: "mappin.and.ellipse"
        ),
        IntentItem(
            id: "markRideEvent",
            titleKey: "app_intent_mark_ride_event_title",
            descriptionKey: "app_intent_mark_ride_event_description",
            contextKey: "automation_guide_intent_local_only",
            systemImageName: "flag.fill"
        ),
        IntentItem(
            id: "openHUD",
            titleKey: "app_intent_open_hud_title",
            descriptionKey: "app_intent_open_hud_description",
            contextKey: "automation_guide_intent_foreground",
            systemImageName: "rectangle.inset.filled"
        ),
        IntentItem(
            id: "navigate",
            titleKey: "app_intent_navigate_title",
            descriptionKey: "app_intent_navigate_description",
            contextKey: "automation_guide_intent_foreground",
            systemImageName: "arrow.triangle.turn.up.right.diamond.fill"
        ),
        IntentItem(
            id: "findFuel",
            titleKey: "app_intent_find_fuel_title",
            descriptionKey: "app_intent_find_fuel_description",
            contextKey: "automation_guide_intent_foreground",
            systemImageName: "fuelpump.fill"
        ),
        IntentItem(
            id: "motorcycleTimer",
            titleKey: "app_intent_timer_short_title",
            descriptionKey: "app_intent_timer_description",
            contextKey: "automation_guide_intent_background",
            systemImageName: "timer"
        ),
        IntentItem(
            id: "departureReminder",
            titleKey: "app_intent_departure_short_title",
            descriptionKey: "app_intent_departure_description",
            contextKey: "automation_guide_intent_background",
            systemImageName: "flag.checkered"
        )
    ]

    static let schemeItems: [SchemeItem] = [
        SchemeItem(
            id: "checkFuel",
            titleKey: "automation_scheme_check_fuel_title",
            descriptionKey: "automation_scheme_check_fuel_description",
            noteKey: "automation_scheme_check_fuel_note",
            examples: ["xp400://checkFuel"],
            systemImageName: "fuelpump.fill"
        ),
        SchemeItem(
            id: "antiTheft",
            titleKey: "automation_scheme_anti_theft_title",
            descriptionKey: "automation_scheme_anti_theft_description",
            noteKey: "automation_scheme_anti_theft_note",
            examples: [
                "xp400://antiTheft?enable=true",
                "xp400://antiTheft?enable=false"
            ],
            systemImageName: "lock.shield"
        ),
        SchemeItem(
            id: "openHUD",
            titleKey: "automation_scheme_open_hud_title",
            descriptionKey: "automation_scheme_open_hud_description",
            noteKey: "automation_scheme_open_hud_note",
            examples: ["xp400://openHUD"],
            systemImageName: "rectangle.inset.filled"
        ),
        SchemeItem(
            id: "openSafety",
            titleKey: "automation_scheme_open_safety_title",
            descriptionKey: "automation_scheme_open_safety_description",
            noteKey: "automation_scheme_open_safety_note",
            examples: ["xp400://openSafety"],
            systemImageName: "shield.checkered"
        ),
        SchemeItem(
            id: "confirmGasStationRoute",
            titleKey: "automation_scheme_confirm_fuel_title",
            descriptionKey: "automation_scheme_confirm_fuel_description",
            noteKey: "automation_scheme_confirm_fuel_note",
            examples: ["xp400://confirmGasStationRoute"],
            systemImageName: "location.magnifyingglass"
        ),
        SchemeItem(
            id: "navigate",
            titleKey: "automation_scheme_navigate_title",
            descriptionKey: "automation_scheme_navigate_description",
            noteKey: "automation_scheme_navigate_note",
            examples: ["xp400://navigate?destination=%E7%8F%A0%E6%B1%9F%E6%96%B0%E5%9F%8E"],
            systemImageName: "arrow.triangle.turn.up.right.diamond.fill"
        ),
        SchemeItem(
            id: "openAlarms",
            titleKey: "automation_scheme_open_alarms_title",
            descriptionKey: "automation_scheme_open_alarms_description",
            noteKey: "automation_scheme_open_alarms_note",
            examples: ["xp400://openAlarms"],
            systemImageName: "bell.badge.fill"
        )
    ]
}

@MainActor
final class PTAutomationGuideViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private lazy var systemSettingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(localized("automation_guide_system_settings"), for: .normal)
        button.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.5).cgColor
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        button.addActionHandlers { [weak self] _ in
            self?.openSystemSettings()
        }
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("automation_guide_title")
        view.backgroundColor = .black
        configureLayout()
        reloadContent()
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func reloadContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeIntroCard())
        contentStack.addArrangedSubview(makeShortcutsCard())
        contentStack.addArrangedSubview(makeSectionHeader(
            title: localized("automation_guide_intents_section"),
            body: localized("automation_guide_intents_explanation")
        ))
        PTAutomationGuideCatalog.intentItems.forEach {
            contentStack.addArrangedSubview(makeIntentCard(item: $0))
        }
        contentStack.addArrangedSubview(makeSectionHeader(
            title: localized("automation_guide_scheme_section"),
            body: localized("automation_guide_scheme_explanation")
        ))
        PTAutomationGuideCatalog.schemeItems.forEach {
            contentStack.addArrangedSubview(makeSchemeCard(item: $0))
        }
        contentStack.addArrangedSubview(makeFAQCard())
    }

    private func makeIntroCard() -> UIView {
        makeCard(
            title: localized("automation_guide_title"),
            body: makeBodyLabel(text: localized("automation_guide_summary")),
            icon: "sparkles"
        )
    }

    private func makeShortcutsCard() -> UIView {
        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 10

        let explanation = makeBodyLabel(text: localized("automation_guide_shortcuts_explanation"))
        body.addArrangedSubview(explanation)

        let shortcutsButton = ShortcutsUIButton(style: .darkOutline)
        shortcutsButton.accessibilityIdentifier = "automationGuide.shortcutsButton"
        shortcutsButton.accessibilityHint = localized("automation_guide_shortcuts_button_hint")
        shortcutsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        body.addArrangedSubview(shortcutsButton)
        body.addArrangedSubview(systemSettingsButton)

        return makeCard(
            title: localized("automation_guide_shortcuts_section"),
            body: body,
            icon: "wand.and.stars"
        )
    }

    private func makeSectionHeader(title: String, body: String) -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(makeBodyLabel(text: body))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    private func makeIntentCard(item: PTAutomationGuideCatalog.IntentItem) -> UIView {
        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 8

        body.addArrangedSubview(makeBodyLabel(text: localized(item.descriptionKey)))
        body.addArrangedSubview(makeTagLabel(text: localized(item.contextKey)))
        if let tip = makeSiriTip(for: item.id) {
            body.addArrangedSubview(tip)
        }

        let card = makeCard(
            title: localized(item.titleKey),
            body: body,
            icon: item.systemImageName
        )
        card.accessibilityIdentifier = "automationGuide.intent.\(item.id)"
        return card
    }

    private func makeSiriTip(for id: String) -> SiriTipUIView? {
        let tip = SiriTipUIView(style: .dark)
        tip.allowsDismissal = false

        switch id {
        case "vehicleStatus":
            tip.setIntent(intent: PTGetVehicleStatusIntent())
        case "parkedLocation":
            tip.setIntent(intent: PTGetParkedLocationIntent())
        case "markRideEvent":
            tip.setIntent(intent: PTMarkRideEventIntent())
        case "openHUD":
            tip.setIntent(intent: PTOpenHUDIntent())
        case "navigate":
            tip.setIntent(intent: PTNavigateToDestinationIntent())
        case "findFuel":
            tip.setIntent(intent: PTFindFuelStationIntent())
        default:
            return nil
        }

        tip.isPresented = true
        tip.accessibilityIdentifier = "automationGuide.siriTip.\(id)"
        return tip
    }

    private func makeSchemeCard(item: PTAutomationGuideCatalog.SchemeItem) -> UIView {
        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 8

        body.addArrangedSubview(makeBodyLabel(text: localized(item.descriptionKey)))
        body.addArrangedSubview(makeTagLabel(text: localized(item.noteKey)))

        for (index, example) in item.examples.enumerated() {
            body.addArrangedSubview(makeCodeRow(example: example, itemID: item.id, index: index))
        }

        let card = makeCard(
            title: localized(item.titleKey),
            body: body,
            icon: item.systemImageName
        )
        card.accessibilityIdentifier = "automationGuide.scheme.\(item.id)"
        return card
    }

    private func makeCodeRow(example: String, itemID: String, index: Int) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let codeLabel = UILabel()
        codeLabel.text = example
        codeLabel.textColor = .systemGray2
        codeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byCharWrapping
        codeLabel.adjustsFontForContentSizeCategory = true
        codeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        codeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copyButton = UIButton(type: .system)
        copyButton.setTitle(localized("automation_guide_scheme_copy"), for: .normal)
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.baseBackgroundColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.8)
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9)
        copyButton.configuration = buttonConfiguration
        copyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        copyButton.layer.cornerRadius = 7
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.accessibilityIdentifier = "automationGuide.scheme.\(itemID).copy.\(index)"
        copyButton.addActionHandlers { [weak self] _ in
            self?.copyScheme(example)
        }

        row.addArrangedSubview(codeLabel)
        row.addArrangedSubview(copyButton)
        return row
    }

    private func makeFAQCard() -> UIView {
        makeCard(
            title: localized("automation_guide_faq_section"),
            body: makeBodyLabel(text: localized("automation_guide_faq")),
            icon: "questionmark.circle"
        )
    }

    private func makeCard(title: String, body: UIView, icon: String) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.1, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.3).cgColor

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.tintColor = PTDashboardConfig.shared.appMainColor
        imageView.contentMode = .scaleAspectFit
        imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        titleRow.addArrangedSubview(imageView)
        titleRow.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(body)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeBodyLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeTagLabel(text: String) -> UILabel {
        let label = makeBodyLabel(text: text)
        label.textColor = .systemGray2
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func copyScheme(_ example: String) {
        UIPasteboard.general.string = example
        let feedback = localized("automation_guide_scheme_copied")
        PTNSLogConsole("[自动化说明] \(feedback): \(example)")
        UIAccessibility.post(notification: .announcement, argument: feedback)
        PTProgressHUD.show(text: feedback)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}
