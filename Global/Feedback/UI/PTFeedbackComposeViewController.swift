//
//  PTFeedbackComposeViewController.swift
//  CrazyDashboard
//
//  Build74: optional privacy-sanitized screenshot attachments.
//

import PhotosUI
import UIKit
import PooTools
import SnapKit
import SwifterSwift

@MainActor
final class PTFeedbackComposeViewController: PTMotoBaseViewController {

    private var draft = PTFeedbackDraft()
    private var isSubmitting = false
    private var attachmentDrafts: [PTFeedbackAttachmentDraft] = []

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        return view
    }()

    private lazy var contentView = UIView()

    private lazy var categoryButton: UIButton = makePickerButton()
    private lazy var moduleButton: UIButton = makePickerButton()

    private lazy var titleField: UITextField = {
        let view = UITextField()
        view.placeholder = PTFeedbackPresentation.text(
            "feedback_title_placeholder",
            fallback: "简要描述问题"
        )
        view.backgroundColor = .secondarySystemBackground
        view.textColor = .label
        view.clearButtonMode = .whileEditing
        view.returnKeyType = .next
        view.layer.cornerRadius = 10
        view.leftView = UIView(frame: .init(x: 0, y: 0, width: 12, height: 1))
        view.leftViewMode = .always
        return view
    }()

    private lazy var bodyTextView: UITextView = {
        let view = UITextView()
        view.backgroundColor = .secondarySystemBackground
        view.textColor = .label
        view.font = .systemFont(ofSize: 16)
        view.layer.cornerRadius = 10
        view.textContainerInset = .init(top: 12, left: 8, bottom: 12, right: 8)
        return view
    }()

    private lazy var diagnosticsLabel = makeSwitchTitle(
        PTFeedbackPresentation.text(
            "feedback_include_diagnostics",
            fallback: "附带匿名诊断摘要"
        )
    )

    private lazy var diagnosticsSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = true
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        return view
    }()

    private lazy var telemetryLabel = makeSwitchTitle(
        PTFeedbackPresentation.text(
            "feedback_link_telemetry",
            fallback: "关联当前 Telemetry Session"
        )
    )

    private lazy var telemetrySwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = false
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        return view
    }()

    private lazy var attachmentButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setTitleColor(.label, for: .normal)
        view.backgroundColor = .secondarySystemBackground
        view.viewCorner(radius: 10)
        view.addActionHandlers { [weak self] _ in
            self?.presentScreenshotPicker()
        }
        return view
    }()

    private lazy var attachmentLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .systemFont(ofSize: 12)
        view.textColor = .secondaryLabel
        return view
    }()

    private lazy var privacyLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .systemFont(ofSize: 12)
        view.textColor = .secondaryLabel
        view.text = PTFeedbackPresentation.text(
            "feedback_privacy_detail_build74",
            fallback: "反馈正文会先脱敏并加密。可选截图会在设备端重新绘制为 JPEG，移除 EXIF/GPS metadata 后再独立加密上传；最多 3 张，每张不超过 2 MB。Telemetry 关联只引用现有匿名 Session，不会为反馈启动或结束采集。"
        )
        return view
    }()

    private lazy var submitButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setTitle(
            PTFeedbackPresentation.text("feedback_submit", fallback: "提交反馈"),
            for: .normal
        )
        view.setTitleColor(.white, for: .normal)
        view.setBackgroundColor(
            color: PTDashboardConfig.shared.appMainColor,
            forState: .normal
        )
        view.addActionHandlers { [weak self] _ in
            self?.submit()
        }
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTFeedbackPresentation.text(
            "feedback_compose_title",
            fallback: "提交反馈"
        )
        setupUI()
        rebuildMenus()
        refreshAttachmentUI()

        Task {
            if let saved = await PTFeedbackDraftStore.shared.load() {
                draft = saved
                applyDraft()
            }
            await refreshTelemetryAvailability()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !isSubmitting else { return }
        updateDraftFromUI()
        let snapshot = draft
        Task { await PTFeedbackDraftStore.shared.save(snapshot) }
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        [
            categoryButton,
            moduleButton,
            titleField,
            bodyTextView,
            diagnosticsLabel,
            diagnosticsSwitch,
            telemetryLabel,
            telemetrySwitch,
            attachmentButton,
            attachmentLabel,
            privacyLabel,
            submitButton
        ].forEach(contentView.addSubview)

        scrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.left.right.bottom.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }
        categoryButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.left.right.equalToSuperview().inset(20)
            make.height.equalTo(44)
        }
        moduleButton.snp.makeConstraints { make in
            make.top.equalTo(categoryButton.snp.bottom).offset(10)
            make.left.right.height.equalTo(categoryButton)
        }
        titleField.snp.makeConstraints { make in
            make.top.equalTo(moduleButton.snp.bottom).offset(16)
            make.left.right.equalTo(categoryButton)
            make.height.equalTo(46)
        }
        bodyTextView.snp.makeConstraints { make in
            make.top.equalTo(titleField.snp.bottom).offset(12)
            make.left.right.equalTo(categoryButton)
            make.height.equalTo(190)
        }
        diagnosticsLabel.snp.makeConstraints { make in
            make.top.equalTo(bodyTextView.snp.bottom).offset(22)
            make.left.equalTo(categoryButton)
            make.right.lessThanOrEqualTo(diagnosticsSwitch.snp.left).offset(-12)
            make.centerY.equalTo(diagnosticsSwitch)
        }
        diagnosticsSwitch.snp.makeConstraints { make in
            make.right.equalTo(categoryButton)
            make.top.equalTo(bodyTextView.snp.bottom).offset(18)
        }
        telemetryLabel.snp.makeConstraints { make in
            make.top.equalTo(diagnosticsSwitch.snp.bottom).offset(18)
            make.left.equalTo(categoryButton)
            make.right.lessThanOrEqualTo(telemetrySwitch.snp.left).offset(-12)
            make.centerY.equalTo(telemetrySwitch)
        }
        telemetrySwitch.snp.makeConstraints { make in
            make.right.equalTo(categoryButton)
            make.top.equalTo(diagnosticsSwitch.snp.bottom).offset(14)
        }
        attachmentButton.snp.makeConstraints { make in
            make.top.equalTo(telemetrySwitch.snp.bottom).offset(20)
            make.left.right.equalTo(categoryButton)
            make.height.equalTo(44)
        }
        attachmentLabel.snp.makeConstraints { make in
            make.top.equalTo(attachmentButton.snp.bottom).offset(8)
            make.left.right.equalTo(categoryButton)
        }
        privacyLabel.snp.makeConstraints { make in
            make.top.equalTo(attachmentLabel.snp.bottom).offset(16)
            make.left.right.equalTo(categoryButton)
        }
        submitButton.snp.makeConstraints { make in
            make.top.equalTo(privacyLabel.snp.bottom).offset(24)
            make.left.right.equalTo(categoryButton)
            make.height.equalTo(48)
            make.bottom.equalToSuperview().inset(30)
        }

        categoryButton.viewCorner(radius: 10)
        moduleButton.viewCorner(radius: 10)
        submitButton.viewCorner(radius: 10)
    }

    private func makePickerButton() -> UIButton {
        let view = UIButton(type: .system)
        view.contentHorizontalAlignment = .leading
        view.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        view.setTitleColor(.label, for: .normal)
        view.backgroundColor = .secondarySystemBackground
        view.showsMenuAsPrimaryAction = true
        view.contentEdgeInsets = .init(top: 0, left: 12, bottom: 0, right: 12)
        return view
    }

    private func makeSwitchTitle(_ text: String) -> UILabel {
        let view = UILabel()
        view.numberOfLines = 0
        view.textColor = .white
        view.font = .systemFont(ofSize: 15)
        view.text = text
        return view
    }

    private func rebuildMenus() {
        categoryButton.setTitle(
            PTFeedbackPresentation.text("feedback_category_prefix", fallback: "类型")
            + ": " + PTFeedbackPresentation.categoryTitle(draft.category),
            for: .normal
        )
        categoryButton.menu = UIMenu(children: PTFeedbackCategory.allCases.map { value in
            UIAction(
                title: PTFeedbackPresentation.categoryTitle(value),
                state: draft.category == value ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                draft.category = value
                rebuildMenus()
            }
        })

        moduleButton.setTitle(
            PTFeedbackPresentation.text("feedback_module_prefix", fallback: "模块")
            + ": " + PTFeedbackPresentation.moduleTitle(draft.module),
            for: .normal
        )
        moduleButton.menu = UIMenu(children: PTFeedbackModule.allCases.map { value in
            UIAction(
                title: PTFeedbackPresentation.moduleTitle(value),
                state: draft.module == value ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                draft.module = value
                rebuildMenus()
            }
        })
    }

    private func applyDraft() {
        titleField.text = draft.title
        bodyTextView.text = draft.body
        diagnosticsSwitch.isOn = draft.includeDiagnostics
        telemetrySwitch.isOn = draft.linkCurrentTelemetrySession
        rebuildMenus()
    }

    private func updateDraftFromUI() {
        draft.title = titleField.text ?? ""
        draft.body = bodyTextView.text ?? ""
        draft.includeDiagnostics = diagnosticsSwitch.isOn
        draft.linkCurrentTelemetrySession = telemetrySwitch.isOn
    }

    private func refreshTelemetryAvailability() async {
        let telemetryLink = await PTFeedbackTelemetryLink.currentLink()
        telemetrySwitch.isEnabled = telemetryLink != nil
        if telemetryLink == nil { telemetrySwitch.isOn = false }
    }

    private func refreshAttachmentUI() {
        let count = attachmentDrafts.count
        let buttonTitle = count == 0
            ? PTFeedbackPresentation.text("feedback_add_screenshot", fallback: "添加截图（可选）")
            : PTFeedbackPresentation.text("feedback_manage_screenshot", fallback: "重新选择截图") + " (\(count)/3)"
        attachmentButton.setTitle(buttonTitle, for: .normal)
        attachmentLabel.text = count == 0
            ? PTFeedbackPresentation.text(
                "feedback_attachment_hint",
                fallback: "使用系统照片选择器；CrazyDashboard 不需要读取整个照片库。"
            )
            : PTFeedbackPresentation.text(
                "feedback_attachment_ready",
                fallback: "截图已在内存中重新编码并移除 metadata，提交时会独立加密。"
            )
    }

    private func presentScreenshotPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 3
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func submit() {
        guard !isSubmitting else { return }
        updateDraftFromUI()

        let draftSnapshot = draft
        let context = PTFeedbackContextBuilder.make()
        let diagnostics = draftSnapshot.includeDiagnostics
            ? PTFeedbackDiagnosticsBuilder.make()
            : nil
        let attachments = attachmentDrafts

        isSubmitting = true
        submitButton.isEnabled = false
        submitButton.setTitle(
            PTFeedbackPresentation.text("feedback_submitting", fallback: "提交中…"),
            for: .normal
        )

        Task {
            let telemetryLink: PTFeedbackTelemetryLinkSnapshot?
            if draftSnapshot.linkCurrentTelemetrySession {
                telemetryLink = await PTFeedbackTelemetryLink.currentLink()
            } else {
                telemetryLink = nil
            }

            do {
                let result = try await PTFeedbackManager.shared.submit(
                    draft: draftSnapshot,
                    context: context,
                    diagnostics: diagnostics,
                    telemetrySessionID: telemetryLink?.sessionID,
                    telemetrySessionOffsetMilliseconds: telemetryLink?.sessionOffsetMilliseconds
                )

                if !attachments.isEmpty {
                    await PTFeedbackAttachmentManager.shared.submit(
                        feedbackID: result.feedbackID,
                        drafts: attachments
                    )
                }

                await PTFeedbackDraftStore.shared.clear()
                attachmentDrafts.removeAll()

                let message = result.uploadedImmediately
                    ? PTFeedbackPresentation.text(
                        "feedback_submitted_cloud_build74",
                        fallback: attachments.isEmpty
                            ? "反馈已加密并提交到 CloudKit。"
                            : "反馈已提交；截图附件已独立加密并进入上传队列。"
                    )
                    : PTFeedbackPresentation.text(
                        "feedback_submitted_queued",
                        fallback: "反馈已安全保存在本地队列，网络或 iCloud 恢复后会重试。"
                    )

                showResult(
                    title: PTFeedbackPresentation.text("feedback_submit_success", fallback: "已收到"),
                    message: message,
                    popAfterDismiss: true
                )
            } catch {
                showResult(
                    title: PTFeedbackPresentation.text("feedback_submit_failed", fallback: "提交失败"),
                    message: error.localizedDescription,
                    popAfterDismiss: false
                )
            }

            isSubmitting = false
            submitButton.isEnabled = true
            submitButton.setTitle(
                PTFeedbackPresentation.text("feedback_submit", fallback: "提交反馈"),
                for: .normal
            )
        }
    }

    private func showResult(title: String, message: String, popAfterDismiss: Bool) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: PTFeedbackPresentation.text("button_confirm", fallback: "确定"),
            style: .default
        ) { [weak self] _ in
            guard popAfterDismiss else { return }
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}

extension PTFeedbackComposeViewController: PHPickerViewControllerDelegate {
    nonisolated func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            guard let self else { return }
            attachmentDrafts.removeAll()

            for result in results.prefix(3) {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                do {
                    let image = try await loadImage(from: result.itemProvider)
                    let draft = try PTFeedbackAttachmentBuilder.sanitizedJPEG(from: image)
                    attachmentDrafts.append(draft)
                } catch {
                    continue
                }
            }
            refreshAttachmentUI()
        }
    }

    private func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? UIImage else {
                    continuation.resume(throwing: PTFeedbackError.storageFailure("无法读取所选截图"))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}
