//
//  PTMotorcycleGarage.swift
//  CrazyDashboard
//
//  EN: Small, main-actor-isolated garage storage for motorcycle-owned records.
//  ES: Almacenamiento pequeño y aislado en el actor principal para registros de cada motocicleta.
//  中文：面向每辆摩托车的小型主线程隔离档案存储。
//

import Foundation

public struct PTGarageMaintenanceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let completedAt: Date
    public let mileageKm: Double
    public let nextDueMileageKm: Double?
    public let notes: String

    nonisolated public init(
        id: UUID = UUID(),
        title: String,
        completedAt: Date = Date(),
        mileageKm: Double,
        nextDueMileageKm: Double? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.completedAt = completedAt
        self.mileageKm = mileageKm
        self.nextDueMileageKm = nextDueMileageKm
        self.notes = notes
    }
}

public struct PTGaragePartRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let partNumber: String
    public let installedAt: Date
    public let mileageKm: Double?
    public let notes: String

    nonisolated public init(
        id: UUID = UUID(),
        name: String,
        partNumber: String = "",
        installedAt: Date = Date(),
        mileageKm: Double? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.partNumber = partNumber
        self.installedAt = installedAt
        self.mileageKm = mileageKm
        self.notes = notes
    }
}

/// EN: Persist only the read-only diagnostic evidence needed for a vehicle history.
/// ES: Solo conserva la evidencia de diagnóstico de solo lectura necesaria para el historial del vehículo.
/// 中文：只保存车辆历史所需的只读诊断证据。
public struct PTGarageDIDRecord: Codable, Equatable, Sendable {
    public let did: String
    public let rawResponse: String
    public let payloadHex: String?
    public let decodedText: String?
    public let status: String
    public let negativeResponseCode: String?

    nonisolated public init(
        did: String,
        rawResponse: String,
        payloadHex: String? = nil,
        decodedText: String? = nil,
        status: String,
        negativeResponseCode: String? = nil
    ) {
        self.did = did
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.decodedText = decodedText
        self.status = status
        self.negativeResponseCode = negativeResponseCode
    }

    nonisolated public init(result: PTOBDIDReadResult) {
        self.init(
            did: result.did,
            rawResponse: result.rawResponse,
            payloadHex: result.payloadHex,
            decodedText: result.decodedText,
            status: result.status.rawValue,
            negativeResponseCode: result.negativeResponseCode
        )
    }
}

public struct PTGarageDiagnosticReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let vin: String
    public let ecuVersion: String
    public let cvn: String
    public let protocolName: String
    public let adapterName: String
    public let supportedCommandCount: Int
    public let didResults: [PTGarageDIDRecord]

    nonisolated public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        vin: String = "",
        ecuVersion: String = "",
        cvn: String = "",
        protocolName: String = "",
        adapterName: String = "",
        supportedCommandCount: Int = 0,
        didResults: [PTGarageDIDRecord] = []
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.vin = vin
        self.ecuVersion = ecuVersion
        self.cvn = cvn
        self.protocolName = protocolName
        self.adapterName = adapterName
        self.supportedCommandCount = max(0, supportedCommandCount)
        self.didResults = didResults
    }

    nonisolated public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        vin: String = "",
        ecuVersion: String = "",
        cvn: String = "",
        protocolName: String = "",
        adapterName: String = "",
        supportedCommandCount: Int = 0,
        didResults: [PTOBDIDReadResult]
    ) {
        self.init(
            id: id,
            capturedAt: capturedAt,
            vin: vin,
            ecuVersion: ecuVersion,
            cvn: cvn,
            protocolName: protocolName,
            adapterName: adapterName,
            supportedCommandCount: supportedCommandCount,
            didResults: didResults.map(PTGarageDIDRecord.init(result:))
        )
    }

    public var successfulDIDCount: Int {
        didResults.filter { $0.status == PTOBDReadStatus.success.rawValue }.count
    }

    public var failedDIDCount: Int {
        didResults.count - successfulDIDCount
    }
}

public struct PTMotorcycleProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var brand: String
    public var model: String
    public var year: Int?
    public var vin: String
    public var odometerKm: Double
    public var maintenanceRecords: [PTGarageMaintenanceRecord]
    public var diagnosticReports: [PTGarageDiagnosticReport]
    public var parts: [PTGaragePartRecord]
    public let createdAt: Date
    public var updatedAt: Date

    nonisolated public init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        model: String = "",
        year: Int? = nil,
        vin: String = "",
        odometerKm: Double = 0,
        maintenanceRecords: [PTGarageMaintenanceRecord] = [],
        diagnosticReports: [PTGarageDiagnosticReport] = [],
        parts: [PTGaragePartRecord] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.model = model
        self.year = year
        self.vin = vin
        self.odometerKm = odometerKm
        self.maintenanceRecords = maintenanceRecords
        self.diagnosticReports = diagnosticReports
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static var defaultXP400GT: PTMotorcycleProfile {
        PTMotorcycleProfile(name: "XP400 GT", brand: "Peugeot", model: "XP400 GT")
    }
}

public struct PTMotorcycleGarageDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let selectedVehicleID: UUID?
    public let vehicles: [PTMotorcycleProfile]

    nonisolated public init(
        schemaVersion: Int = 1,
        selectedVehicleID: UUID? = nil,
        vehicles: [PTMotorcycleProfile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.selectedVehicleID = selectedVehicleID
        self.vehicles = vehicles
    }
}

/// EN: The store keeps the document small, bounded and synchronously available to UIKit.
/// ES: El almacén mantiene el documento pequeño, limitado y disponible de forma síncrona para UIKit.
/// 中文：该存储让档案文档保持小而有界，并同步提供给 UIKit 使用。
@MainActor
public final class PTMotorcycleGarageStore {
    public static let shared = PTMotorcycleGarageStore()
    public static let didChangeNotification = Notification.Name("PTMotorcycleGarageStoreDidChange")

    public static let storageKey = "PTMotorcycleGarageDocument.v1"
    public static let maximumVehicleCount = 32
    public static let maximumMaintenanceCount = 100
    public static let maximumPartCount = 100
    public static let maximumDiagnosticReportCount = 30

    private let userDefaults: UserDefaults
    public private(set) var vehicles: [PTMotorcycleProfile]
    public private(set) var selectedVehicleID: UUID?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: Self.storageKey),
           let document = try? JSONDecoder().decode(PTMotorcycleGarageDocument.self, from: data),
           !document.vehicles.isEmpty {
            self.vehicles = document.vehicles
            self.selectedVehicleID = document.selectedVehicleID
                ?? document.vehicles.first?.id
        } else {
            let defaultVehicle = PTMotorcycleProfile.defaultXP400GT
            self.vehicles = [defaultVehicle]
            self.selectedVehicleID = defaultVehicle.id
            persist(notify: false)
        }

        if selectedVehicleID == nil || !vehicles.contains(where: { $0.id == selectedVehicleID }) {
            selectedVehicleID = vehicles.first?.id
            persist(notify: false)
        }
    }

    public var currentVehicle: PTMotorcycleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first { $0.id == selectedVehicleID }
    }

    @discardableResult
    public func selectVehicle(id: UUID) -> Bool {
        guard vehicles.contains(where: { $0.id == id }) else { return false }
        guard selectedVehicleID != id else { return true }
        selectedVehicleID = id
        persist()
        return true
    }

    @discardableResult
    public func createVehicle(
        name: String,
        brand: String = "",
        model: String = "",
        year: Int? = nil,
        vin: String = "",
        odometerKm: Double = 0
    ) -> PTMotorcycleProfile? {
        guard vehicles.count < Self.maximumVehicleCount else { return nil }
        let normalizedName = normalizeText(name)
        guard !normalizedName.isEmpty,
              let normalizedOdometer = validOdometer(odometerKm) else {
            return nil
        }

        let now = Date()
        let profile = PTMotorcycleProfile(
            name: normalizedName,
            brand: normalizeText(brand),
            model: normalizeText(model),
            year: validYear(year),
            vin: normalizeVIN(vin),
            odometerKm: normalizedOdometer,
            createdAt: now,
            updatedAt: now
        )
        vehicles.append(profile)
        selectedVehicleID = profile.id
        persist()
        return profile
    }

    @discardableResult
    public func deleteVehicle(id: UUID) -> Bool {
        guard vehicles.count > 1,
              let index = vehicles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        vehicles.remove(at: index)
        if selectedVehicleID == id {
            selectedVehicleID = vehicles.first?.id
        }
        persist()
        return true
    }

    @discardableResult
    public func updateOdometer(_ odometerKm: Double, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedOdometer = validOdometer(odometerKm) else {
            return false
        }

        vehicles[index].odometerKm = normalizedOdometer
        touchVehicle(at: index)
        persist()
        return true
    }

    /// EN: Explicitly sync a safe, monotonic odometer sample from the existing dashboard coordinator.
    /// ES: Sincroniza explícitamente una muestra de odómetro segura y monotónica desde el coordinador existente.
    /// 中文：从现有仪表协调器显式同步安全且不倒退的里程数据。
    @discardableResult
    public func syncCurrentVehicleFromLiveData() -> Bool {
        guard let index = indexOfVehicle(nil) else { return false }
        var didChange = false

        if let dashboardData = PTBluetoothServerManager.shared.latestData1,
           let odometer = safeLiveOdometer(dashboardData.odoKm),
           odometer >= vehicles[index].odometerKm {
            if odometer != vehicles[index].odometerKm {
                vehicles[index].odometerKm = odometer
                didChange = true
            }
        }

        let telemetryVIN = normalizeVIN(PTMotoTelemetryManager.shared.obdInfo.vin)
        if vehicles[index].vin.isEmpty, !telemetryVIN.isEmpty {
            vehicles[index].vin = telemetryVIN
            didChange = true
        }

        guard didChange else { return false }
        touchVehicle(at: index)
        persist()
        return true
    }

    @discardableResult
    public func addMaintenance(
        title: String,
        completedAt: Date = Date(),
        mileageKm: Double? = nil,
        nextDueMileageKm: Double? = nil,
        notes: String = "",
        vehicleID: UUID? = nil
    ) -> PTGarageMaintenanceRecord? {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedTitle = nonEmptyText(title),
              let normalizedMileage = validOdometer(mileageKm ?? vehicles[index].odometerKm),
              validOptionalOdometer(nextDueMileageKm) != nil || nextDueMileageKm == nil else {
            return nil
        }

        let record = PTGarageMaintenanceRecord(
            title: normalizedTitle,
            completedAt: completedAt,
            mileageKm: normalizedMileage,
            nextDueMileageKm: validOptionalOdometer(nextDueMileageKm),
            notes: normalizeText(notes)
        )
        vehicles[index].maintenanceRecords.insert(record, at: 0)
        vehicles[index].maintenanceRecords = Array(
            vehicles[index].maintenanceRecords.prefix(Self.maximumMaintenanceCount)
        )
        touchVehicle(at: index)
        persist()
        return record
    }

    @discardableResult
    public func removeMaintenance(id: UUID, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let recordIndex = vehicles[index].maintenanceRecords.firstIndex(where: { $0.id == id }) else {
            return false
        }
        vehicles[index].maintenanceRecords.remove(at: recordIndex)
        touchVehicle(at: index)
        persist()
        return true
    }

    @discardableResult
    public func addPart(
        name: String,
        partNumber: String = "",
        installedAt: Date = Date(),
        mileageKm: Double? = nil,
        notes: String = "",
        vehicleID: UUID? = nil
    ) -> PTGaragePartRecord? {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedName = nonEmptyText(name),
              validOptionalOdometer(mileageKm) != nil || mileageKm == nil else {
            return nil
        }

        let record = PTGaragePartRecord(
            name: normalizedName,
            partNumber: normalizeText(partNumber),
            installedAt: installedAt,
            mileageKm: validOptionalOdometer(mileageKm),
            notes: normalizeText(notes)
        )
        vehicles[index].parts.insert(record, at: 0)
        vehicles[index].parts = Array(vehicles[index].parts.prefix(Self.maximumPartCount))
        touchVehicle(at: index)
        persist()
        return record
    }

    @discardableResult
    public func removePart(id: UUID, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let partIndex = vehicles[index].parts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        vehicles[index].parts.remove(at: partIndex)
        touchVehicle(at: index)
        persist()
        return true
    }

    @discardableResult
    public func addDiagnosticReport(
        _ report: PTGarageDiagnosticReport,
        vehicleID: UUID? = nil
    ) -> Bool {
        guard let index = indexOfVehicle(vehicleID) else { return false }
        vehicles[index].diagnosticReports.insert(report, at: 0)
        vehicles[index].diagnosticReports = Array(
            vehicles[index].diagnosticReports.prefix(Self.maximumDiagnosticReportCount)
        )
        if vehicles[index].vin.isEmpty, !report.vin.isEmpty {
            vehicles[index].vin = report.vin
        }
        touchVehicle(at: index)
        persist()
        return true
    }

    /// EN: Save only the currently connected adapter's read-only identity and DID evidence.
    /// ES: Guarda únicamente la identidad y la evidencia DID de solo lectura del adaptador conectado.
    /// 中文：只保存当前已连接适配器的只读身份信息和 DID 证据。
    @discardableResult
    public func saveCurrentOBDSnapshot(
        didResults: [PTOBDIDReadResult] = [],
        vehicleID: UUID? = nil
    ) -> PTGarageDiagnosticReport? {
        guard PTMotoTelemetryManager.shared.isConnected,
              indexOfVehicle(vehicleID) != nil else {
            return nil
        }

        let info = PTMotoTelemetryManager.shared.obdInfo
        let adapterName = nonEmptyText(info.moudleInfo.deviceName)
            ?? nonEmptyText(info.aitName)
            ?? ""
        let hasEvidence = !info.vin.isEmpty
            || !info.ecuVersion.isEmpty
            || !info.cvn.isEmpty
            || !info.supportCommand.isEmpty
            || !didResults.isEmpty
        guard hasEvidence else { return nil }

        let report = PTGarageDiagnosticReport(
            vin: normalizeVIN(info.vin),
            ecuVersion: normalizeText(info.ecuVersion),
            cvn: normalizeText(info.cvn),
            protocolName: normalizeText(info.atdpName.description),
            adapterName: adapterName,
            supportedCommandCount: info.supportCommand.count,
            didResults: didResults
        )
        return addDiagnosticReport(report, vehicleID: vehicleID) ? report : nil
    }

    @discardableResult
    public func removeDiagnosticReport(id: UUID, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let reportIndex = vehicles[index].diagnosticReports.firstIndex(where: { $0.id == id }) else {
            return false
        }
        vehicles[index].diagnosticReports.remove(at: reportIndex)
        touchVehicle(at: index)
        persist()
        return true
    }

    private func indexOfVehicle(_ vehicleID: UUID?) -> Int? {
        let id = vehicleID ?? selectedVehicleID
        guard let id else { return nil }
        return vehicles.firstIndex { $0.id == id }
    }

    private func touchVehicle(at index: Int) {
        vehicles[index].updatedAt = Date()
    }

    private func persist(notify: Bool = true) {
        let document = PTMotorcycleGarageDocument(
            selectedVehicleID: selectedVehicleID,
            vehicles: vehicles
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private func normalizeText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(160))
    }

    private func nonEmptyText(_ value: String) -> String? {
        let normalized = normalizeText(value)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeVIN(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        return String(normalized.prefix(64))
    }

    private func validOdometer(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= 2_000_000 else { return nil }
        return value
    }

    private func validOptionalOdometer(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return validOdometer(value)
    }

    private func validYear(_ value: Int?) -> Int? {
        guard let value, (1900...2200).contains(value) else { return nil }
        return value
    }

    private func safeLiveOdometer(_ value: Double) -> Double? {
        validOdometer(value)
    }
}
