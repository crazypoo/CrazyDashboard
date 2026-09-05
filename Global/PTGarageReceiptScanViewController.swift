//
//  PTGarageReceiptScanViewController.swift
//  CrazyDashboard
//
//  EN: User-confirmed receipt OCR for garage refuel and maintenance records.
//  ES: OCR de recibos con confirmación del usuario para repostajes y mantenimientos.
//  中文：用于车库加油和保养记录、且必须经过用户确认的单据识别。
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Vision
import PooTools

// EN: This draft is editable and never writes to the garage by itself.
// ES: Este borrador se puede editar y nunca escribe en el garaje por sí solo.
// 中文：草稿可编辑，绝不会自行写入车库。
public struct PTReceiptDraft: Equatable, Sendable {
    public var title: String
    public var odometerKm: Double?
    public var liters: Double?
    public var amount: Double?
    public var currency: String?
    public var date: Date?
    public var notes: String

    public init(
        title: String = "",
        odometerKm: Double? = nil,
        liters: Double? = nil,
        amount: Double? = nil,
        currency: String? = nil,
        date: Date? = nil,
        notes: String = ""
    ) {
        self.title = title
        self.odometerKm = odometerKm
        self.liters = liters
        self.amount = amount
        self.currency = currency
        self.date = date
        self.notes = notes
    }

    // EN: Extract only conservative numeric hints; the rider confirms every value before saving.
    // ES: Extrae solo indicios numéricos conservadores; el piloto confirma cada valor antes de guardar.
    // 中文：只提取保守的数字提示，保存前由骑手确认每一个字段。
    public static func fromRecognizedText(_ text: String) -> PTReceiptDraft {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let title = normalized
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let odometer = number(
            matching: normalized,
            patterns: [
                "(?i)(?:odometer|mileage|kilomet(?:er|re)|公里|里程)\\s*[:：#]?\\s*([0-9][0-9.,]*)"
            ]
        )
        let liters = number(
            matching: normalized,
            patterns: ["(?i)([0-9][0-9.,]*)\\s*(?:l|lt|liter|litre|升)\\b"]
        )
        let amount = number(
            matching: normalized,
            patterns: [
                "(?i)(?:total|amount|price|合计|金额|总计)\\s*[:：]?\\s*(?:[A-Z]{3}|[$€£¥])?\\s*([0-9][0-9.,]*)",
                "(?:[$€£¥])\\s*([0-9][0-9.,]*)"
            ]
        )
        let currency = currency(matching: normalized)
        let date = date(matching: normalized)

        return PTReceiptDraft(
            title: title,
            odometerKm: odometer,
            liters: liters,
            amount: amount,
            currency: currency,
            date: date,
            notes: normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func number(matching text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            let raw = String(text[range])
            if let value = normalizedDouble(raw) {
                return value
            }
        }
        return nil
    }

    private static func normalizedDouble(_ value: String) -> Double? {
        let compact = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
        let normalized: String
        if compact.contains(","), compact.contains(".") {
            normalized = compact.lastIndex(of: ",").map { commaIndex in
                let dotIndex = compact.lastIndex(of: ".")!
                if commaIndex > dotIndex {
                    return compact.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                }
                return compact.replacingOccurrences(of: ",", with: "")
            } ?? compact
        } else {
            normalized = compact.replacingOccurrences(of: ",", with: ".")
        }
        return Double(normalized)
    }

    private static func currency(matching text: String) -> String? {
        let pattern = "(?i)\\b(EUR|USD|GBP|CNY|TRY|CHF|CAD|AUD|JPY)\\b|([$€£¥])"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).uppercased()
        }
        if match.numberOfRanges > 2, let range = Range(match.range(at: 2), in: text) {
            return String(text[range])
        }
        return nil
    }

    private static func date(matching text: String) -> Date? {
        let pattern = "\\b(20\\d{2}[-/.]\\d{1,2}[-/.]\\d{1,2}|\\d{1,2}[-/.]\\d{1,2}[-/.]20\\d{2})\\b"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[range]).replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "dd-MM-yyyy", "MM-dd-yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

// EN: A small UIKit editor keeps the import flow explicit and reversible.
// ES: Un editor UIKit pequeño mantiene el flujo de importación explícito y reversible.
// 中文：轻量 UIKit 编辑器让导入流程明确且可撤销。
@MainActor
final class PTGarageReceiptScanViewController: PTMotoBaseViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let store: PTMotorcycleGarageStore
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private let recognizedTextView = UITextView()
    private let modeControl = UISegmentedControl()
    private let titleField = UITextField()
    private let odometerField = UITextField()
    private let litersField = UITextField()
    private let amountField = UITextField()
    private let currencyField = UITextField()
    private let dateField = UITextField()
    private let notesField = UITextView()

    lazy var saveButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(localized("garage_receipt_save"), for: .normal)
        view.addActionHandlers(handler: { _ in
            self.saveDraft()
        })
        view.bounds = .init(origin: .zero, size: .init(width: view.sizeFor().width + 20, height: PTAppBaseConfig.share.navBarButtonSize))
        return view
    }()
    
    init(store: PTMotorcycleGarageStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("garage_receipt_scan_title")
        view.backgroundColor = .black
        configureView()
        configureFields()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [saveButton])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    private func configureView() {

        let photoButton = makeButton(title: localized("garage_receipt_choose_photo"), action: #selector(choosePhoto))
        let cameraButton = makeButton(title: localized("garage_receipt_camera"), action: #selector(openCamera))
        let recognizeButton = makeButton(title: localized("garage_receipt_recognize"), action: #selector(recognizeCurrentImage))

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        statusLabel.textColor = .systemGray
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)

        recognizedTextView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        recognizedTextView.textColor = .white
        recognizedTextView.font = .systemFont(ofSize: 14)
        recognizedTextView.layer.cornerRadius = 10
        recognizedTextView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        modeControl.insertSegment(withTitle: localized("garage_receipt_refuel"), at: 0, animated: false)
        modeControl.insertSegment(withTitle: localized("garage_receipt_maintenance"), at: 1, animated: false)
        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor

        notesField.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        notesField.textColor = .white
        notesField.font = .systemFont(ofSize: 14)
        notesField.layer.cornerRadius = 10
        notesField.heightAnchor.constraint(equalToConstant: 90).isActive = true

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.alignment = .fill
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let actionRow = UIStackView(arrangedSubviews: [photoButton, cameraButton, recognizeButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually

        contentStack.addArrangedSubview(imageView)
        contentStack.addArrangedSubview(actionRow)
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(recognizedTextView)
        contentStack.addArrangedSubview(modeControl)
        contentStack.addArrangedSubview(titleField)
        contentStack.addArrangedSubview(odometerField)
        contentStack.addArrangedSubview(litersField)
        contentStack.addArrangedSubview(amountField)
        contentStack.addArrangedSubview(currencyField)
        contentStack.addArrangedSubview(dateField)
        contentStack.addArrangedSubview(notesField)
    }

    private func configureFields() {
        titleField.placeholder = localized("garage_receipt_title")
        odometerField.placeholder = localized("garage_receipt_odometer")
        litersField.placeholder = localized("garage_receipt_liters")
        amountField.placeholder = localized("garage_receipt_amount")
        currencyField.placeholder = localized("garage_receipt_currency")
        dateField.placeholder = localized("garage_receipt_date")
        notesField.text = ""
        notesField.accessibilityLabel = localized("garage_notes")
        [titleField, odometerField, litersField, amountField, currencyField, dateField].forEach {
            $0.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            $0.textColor = .white
            $0.tintColor = PTDashboardConfig.shared.appMainColor
            $0.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
            $0.leftViewMode = .always
            $0.heightAnchor.constraint(equalToConstant: 42).isActive = true
            $0.layer.cornerRadius = 9
        }
        [odometerField, litersField, amountField].forEach { $0.keyboardType = .decimalPad }
        dateField.keyboardType = .numbersAndPunctuation
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = PTDashboardConfig.shared.appMainColor
        button.layer.cornerRadius = 9
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return button
    }

    @objc private func choosePhoto() {
//        var configuration = PHPickerConfiguration(photoLibrary: .shared())
//        configuration.filter = .images
//        configuration.selectionLimit = 1
//        present(PHPickerViewController(configuration: configuration), animated: true)
        PTMediaLibConfig.share.allowTakePhotoInLibrary = false
        PTMediaLibConfig.share.allowEditImage = false
        PTMediaLibConfig.share.allowSelectImage = true
        PTMediaLibConfig.share.allowSelectVideo = false
        PTMediaLibConfig.share.allowSelectGif = false
        PTMediaLibConfig.share.allowEditVideo = false
        PTMediaLibConfig.share.maxSelectCount = 1
        PTMediaLibConfig.share.allowEditImage = false
        let cam = PTCameraConfig()
        cam.allowTakePhoto = true
        cam.allowRecordVideo = false
        PTMediaLibConfig.share.cameraConfiguration = cam

        let vc = PTMediaLibViewController()
        vc.mediaLibShow()
        vc.selectImageBlock = { result, isOriginal in
            if !result.isEmpty,let firstImge = result.first?.image,let imageData = firstImge.jpegData(compressionQuality: 1) {
                self.receive(imageData: imageData)
            } else {
                PTGCDManager.shared.runOnMain {}
            }
        }
    }

    @objc private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showMessage(localized("garage_receipt_camera_unavailable"))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func recognizeCurrentImage() {
        guard let image = imageView.image, let data = image.jpegData(compressionQuality: 0.9) else {
            showMessage(localized("garage_receipt_need_photo"))
            return
        }
        receive(imageData: data)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                self?.receive(imageData: data)
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        receive(imageData: data)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
    }

    private func receive(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        imageView.image = image
        statusLabel.text = localized("garage_receipt_recognizing")
        PTVision.share.findText(withImage: image,recognitionLanguages: ["zh-Hans", "en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "tr-TR"]) { resultText, textObservations in
            let text = textObservations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            self.recognizedTextView.text = text
            let draft = PTReceiptDraft.fromRecognizedText(text)
            self.apply(draft: draft)
            self.statusLabel.text = text.isEmpty
                ? self.localized("garage_receipt_no_text")
                : self.localized("garage_receipt_review_hint")
        }
    }

    private func apply(draft: PTReceiptDraft) {
        titleField.text = draft.title
        odometerField.text = draft.odometerKm.map { String(format: "%.1f", $0) }
        litersField.text = draft.liters.map { String(format: "%.2f", $0) }
        amountField.text = draft.amount.map { String(format: "%.2f", $0) }
        currencyField.text = draft.currency
        dateField.text = draft.date.map { Self.dateFormatter.string(from: $0) }
        notesField.text = draft.notes
    }

    @objc private func saveDraft() {
        guard store.currentVehicle != nil else {
            showMessage(localized("garage_no_vehicle"))
            return
        }

        let odometer = optionalDouble(odometerField.text)
        let amount = optionalDouble(amountField.text)
        let date = optionalDate(dateField.text)
        let currency = currencyField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = notesField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        if modeControl.selectedSegmentIndex == 0 {
            guard let odometer,
                  let liters = optionalDouble(litersField.text),
                  liters > 0 else {
                showMessage(localized("garage_receipt_refuel_required"))
                return
            }
            success = store.addRefuel(
                date: date ?? Date(),
                odometerKm: odometer,
                liters: liters,
                amount: amount,
                currency: currency,
                isFullTank: false,
                notes: notes
            ) != nil
        } else {
            success = store.addMaintenance(
                title: title.isEmpty ? localized("garage_maintenance_title") : title,
                completedAt: date ?? Date(),
                mileageKm: odometer,
                notes: notes,
                cost: amount,
                currency: currency
            ) != nil
        }

        if success {
            navigationController?.popViewController(animated: true)
        } else {
            showMessage(localized("garage_invalid_input"))
        }
    }

    private func optionalDouble(_ text: String?) -> Double? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
        if compact.contains(","), compact.contains(".") {
            let commaIndex = compact.lastIndex(of: ",")!
            let dotIndex = compact.lastIndex(of: ".")!
            if commaIndex > dotIndex {
                return Double(compact.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
            }
            return Double(compact.replacingOccurrences(of: ",", with: ""))
        }
        return Double(compact.replacingOccurrences(of: ",", with: "."))
    }

    private func optionalDate(_ text: String?) -> Date? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Self.dateFormatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: localized("alert_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
