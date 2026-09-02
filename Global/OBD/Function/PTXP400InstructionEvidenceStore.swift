//
//  PTXP400InstructionEvidenceStore.swift
//  CrazyDashboard
//
//  EN: Stores observed read-only XP400 responses without promoting them to commands.
//  ES: Guarda respuestas observadas de solo lectura del XP400 sin convertirlas en comandos.
//  中文：保存已观察到的 XP400 只读响应，但不会把它们升级成可执行指令。
//

import Foundation
import UIKit
import PooTools
import SnapKit
import SafeSFSymbols

public struct PTXP400EvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID?
    public let vehicleName: String
    public let vehicleModel: String
    public let vin: String
    public let address: PTOBDDiagnosticAddress
    public let did: String
    public let requestHex: String
    public let rawResponse: String
    public let payloadHex: String?
    public let decodedText: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?
    public let capturedAt: Date
    public let evidenceLevel: PTXP400InstructionEvidenceLevel
    public let source: String

    public init(
        id: UUID = UUID(),
        vehicleID: UUID? = nil,
        vehicleName: String = "",
        vehicleModel: String = "",
        vin: String = "",
        address: PTOBDDiagnosticAddress,
        did: String,
        requestHex: String? = nil,
        rawResponse: String,
        payloadHex: String? = nil,
        decodedText: String? = nil,
        status: PTOBDReadStatus,
        negativeResponseCode: String? = nil,
        capturedAt: Date = Date(),
        evidenceLevel: PTXP400InstructionEvidenceLevel = .observed,
        source: String = "live-read"
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.vehicleName = vehicleName
        self.vehicleModel = vehicleModel
        self.vin = vin
        self.address = address
        self.did = did.uppercased()
        self.requestHex = requestHex ?? "22\(did.uppercased())"
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.decodedText = decodedText
        self.status = status
        self.negativeResponseCode = negativeResponseCode
        self.capturedAt = capturedAt
        self.evidenceLevel = evidenceLevel
        self.source = source
    }

    @MainActor
    public init(result: PTOBDIDReadResult, source: String = "live-read", capturedAt: Date = Date()) {
        let vehicle = PTMotorcycleGarageStore.shared.currentVehicle
        self.init(
            vehicleID: vehicle?.id,
            vehicleName: vehicle?.name ?? "",
            vehicleModel: vehicle?.model ?? "",
            vin: vehicle?.vin ?? "",
            address: result.address,
            did: result.did,
            rawResponse: result.rawResponse,
            payloadHex: result.payloadHex,
            decodedText: result.decodedText,
            status: result.status,
            negativeResponseCode: result.negativeResponseCode,
            capturedAt: capturedAt,
            evidenceLevel: .observed,
            source: source
        )
    }
}

// EN: Evidence is a bounded observation log; only the static catalog controls ordinary UI execution.
// ES: La evidencia es un registro acotado de observaciones; solo el catálogo estático controla la ejecución normal.
// 中文：证据只是有界观察日志，普通 UI 的执行权限仍只由静态目录控制。
@MainActor
public final class PTXP400InstructionEvidenceStore {
    public static let shared = PTXP400InstructionEvidenceStore()
    public static let storageKey = "PTXP400InstructionEvidence.v1"
    public static let maximumRecordCount = 500

    private let userDefaults: UserDefaults
    public private(set) var records: [PTXP400EvidenceRecord]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let decoded = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PTXP400EvidenceRecord].self, from: $0) }
            ?? []
        self.records = Array(decoded.sorted { $0.capturedAt > $1.capturedAt }.prefix(Self.maximumRecordCount))
        persist()
    }

    @discardableResult
    public func record(
        result: PTOBDIDReadResult,
        source: String = "live-read",
        capturedAt: Date = Date()
    ) -> Bool {
        let record = PTXP400EvidenceRecord(result: result, source: source, capturedAt: capturedAt)
        return insert(record, deduplicateWithin: 3)
    }

    @discardableResult
    public func record(
        results: [PTOBDIDReadResult],
        source: String = "live-read",
        capturedAt: Date = Date()
    ) -> Int {
        results.reduce(into: 0) { count, result in
            if record(result: result, source: source, capturedAt: capturedAt) {
                count += 1
            }
        }
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return false }
        persist()
        return true
    }

    public func clear() {
        records.removeAll(keepingCapacity: true)
        persist()
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records.map(ExportRecord.init))
    }

    public func exportCSVData() -> Data {
        var rows = [
            "id,vehicleName,vehicleModel,vin,addressTx,addressRx,did,requestHex,rawResponse,payloadHex,decodedText,status,negativeResponseCode,capturedAt,evidenceLevel,source"
        ]
        rows.append(contentsOf: records.map { record in
            [
                record.id.uuidString,
                record.vehicleName,
                record.vehicleModel,
                Self.redactVIN(record.vin),
                record.address.tx,
                record.address.rx,
                record.did,
                record.requestHex,
                Self.redactResponse(record.rawResponse, did: record.did),
                record.payloadHex ?? "",
                Self.redactVIN(record.decodedText ?? ""),
                record.status.rawValue,
                record.negativeResponseCode ?? "",
                ISO8601DateFormatter().string(from: record.capturedAt),
                record.evidenceLevel.rawValue,
                record.source
            ].map(Self.csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    public func exportURL(format: PTRideSafetyExportFormat) throws -> URL {
        let fileName = "xp400-evidence-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = format == .json ? try exportJSONData() : exportCSVData()
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension PTXP400InstructionEvidenceStore {
    struct ExportRecord: Codable {
        let id: UUID
        let vehicleName: String
        let vehicleModel: String
        let vin: String
        let addressTx: String
        let addressRx: String
        let did: String
        let requestHex: String
        let rawResponse: String
        let payloadHex: String?
        let decodedText: String?
        let status: PTOBDReadStatus
        let negativeResponseCode: String?
        let capturedAt: Date
        let evidenceLevel: PTXP400InstructionEvidenceLevel
        let source: String

        @MainActor
        init(_ record: PTXP400EvidenceRecord) {
            self.id = record.id
            self.vehicleName = record.vehicleName
            self.vehicleModel = record.vehicleModel
            self.vin = PTXP400InstructionEvidenceStore.redactVIN(record.vin)
            self.addressTx = record.address.tx
            self.addressRx = record.address.rx
            self.did = record.did
            self.requestHex = record.requestHex
            self.rawResponse = PTXP400InstructionEvidenceStore.redactResponse(record.rawResponse, did: record.did)
            self.payloadHex = record.payloadHex
            self.decodedText = PTXP400InstructionEvidenceStore.redactVIN(record.decodedText ?? "")
            self.status = record.status
            self.negativeResponseCode = record.negativeResponseCode
            self.capturedAt = record.capturedAt
            self.evidenceLevel = record.evidenceLevel
            self.source = record.source
        }
    }

    func insert(_ record: PTXP400EvidenceRecord, deduplicateWithin interval: TimeInterval) -> Bool {
        guard !records.contains(where: {
            $0.address == record.address &&
            $0.did == record.did &&
            $0.rawResponse == record.rawResponse &&
            abs($0.capturedAt.timeIntervalSince(record.capturedAt)) <= interval
        }) else {
            return false
        }
        records.insert(record, at: 0)
        records = Array(records.prefix(Self.maximumRecordCount))
        persist()
        return true
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    static func redactVIN(_ value: String) -> String {
        guard value.count > 6 else { return value.isEmpty ? "" : "***" }
        return "\(value.prefix(3))***\(value.suffix(3))"
    }

    static func redactResponse(_ value: String, did: String) -> String {
        guard did.uppercased() == "F190" else { return value }
        let clean = value.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard clean.count > 8 else { return value }
        return "\(clean.prefix(8))" + String(repeating: "X", count: min(clean.count - 8, 32))
    }

    static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

@MainActor
final class PTXP400EvidenceViewController: PTListViewController {
    private let cellIdentifier = "PTXP400EvidenceCell"

    public override func installListViewConstraints(_ listView: PTCollectionView) {
        listView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
    }
    
    public override func makeListViewConfiguration() -> PTCollectionViewConfig {
        let cConfig = PTCollectionViewConfig()
        cConfig.viewType = .Normal
        cConfig.itemOriginalX = PTAppBaseConfig.share.defaultViewSpace
        cConfig.itemHeight = 72
        return cConfig
    }
    
    public override func configureListView(_ listView: PTCollectionView) {
        listView.cellInCollection = { collectionView ,dataModel,indexPath in
            if let itemRow = dataModel.rows?[indexPath.row],let cell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.reuseID, for: indexPath) as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                cell.cellModel  = cellModel
                return cell
            }
            return nil
        }
    }
    
    lazy var exportButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.shared.withYou), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.exportAction()
        })
        return view
    }()

    lazy var clearButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.xmark.circleFill), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.clearAction()
        })
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "obd_evidence_title")
        self.showDetail()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [clearButton,exportButton], buttonSpacing: CGFloat.GlobalItemSpacing)
        self.showDetail()
    }

    func showDetail() {
        var mSections = [PTSection]()
        let permissionRows = PTXP400InstructionEvidenceStore.shared.records.map {
            let cellModel = PTFusionCellModel()
            cellModel.name = "\($0.address.tx) → \($0.address.rx) · \($0.did) · \($0.evidenceLevel.rawValue)"
            cellModel.content = "\($0.status.rawValue) · \($0.rawResponse)"
            
            let row = PTRows(ID: PTFusionCell.ID,dataModel: cellModel)
            row.cellClass = PTFusionCell.self
            return row
        }
        let section = PTSection(rows: permissionRows)
        mSections.append(section)
        
        listView.layoutIfNeeded()
        listView.showCollectionDetail(collectionData: mSections)
    }

    @objc private func exportAction() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_export"),
            message: PTDashboardConfig.languageFunc(text: "obd_evidence_export_hint"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: "JSON",
            style: .default
        ) { [weak self] _ in
            self?.share { try PTXP400InstructionEvidenceStore.shared.exportURL(format: .json) }
        })
        alert.addAction(UIAlertAction(
            title: "CSV",
            style: .default
        ) { [weak self] _ in
            self?.share { try PTXP400InstructionEvidenceStore.shared.exportURL(format: .csv) }
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

    @objc private func clearAction() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_clear"),
            message: PTDashboardConfig.languageFunc(text: "obd_evidence_clear_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_clear"),
            style: .destructive
        ) { [weak self] _ in
            PTXP400InstructionEvidenceStore.shared.clear()
            self?.showDetail()
        })
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func share(_ makeURL: () throws -> URL) {
        do {
            let activity = UIActivityViewController(activityItems: [try makeURL()], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            let alert = UIAlertController(title: PTDashboardConfig.languageFunc(text: "alert_title"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
            present(alert, animated: true)
        }
    }
}
