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
    // EN: Optional diagnostic sections keep older garage JSON readable while allowing richer reports.
    // ES: Las secciones diagnósticas opcionales mantienen legible el JSON antiguo y permiten informes más completos.
    // 中文：诊断分区使用可选字段，保证旧车库 JSON 仍可读取，同时支持更完整的报告。
    public let confirmedDTCs: [String]?
    public let mode6Results: [String]?
    public let freezeFrame: [String]?
    public let failureReasons: [String]?

    nonisolated public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        vin: String = "",
        ecuVersion: String = "",
        cvn: String = "",
        protocolName: String = "",
        adapterName: String = "",
        supportedCommandCount: Int = 0,
        didResults: [PTGarageDIDRecord] = [],
        confirmedDTCs: [String]? = nil,
        mode6Results: [String]? = nil,
        freezeFrame: [String]? = nil,
        failureReasons: [String]? = nil
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
        self.confirmedDTCs = confirmedDTCs
        self.mode6Results = mode6Results
        self.freezeFrame = freezeFrame
        self.failureReasons = failureReasons
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

/// EN: Identifies where the stored odometer value came from.
/// ES: Identifica el origen del valor de odómetro almacenado.
/// 中文：标识车库中保存的里程数值来源。
public enum PTMotorcycleOdometerSource: String, Codable, Sendable {
    case manual
    case dashboard
    case mock
}

public struct PTMotorcycleProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var brand: String
    public var model: String
    public var year: Int?
    public var vin: String
    public var odometerKm: Double
    public var odometerSource: PTMotorcycleOdometerSource?
    // EN: Dashboard identity is local association metadata, not an authentication credential.
    // ES: La identidad del tablero solo sirve para asociar datos localmente, no es una credencial de autenticación.
    // 中文：仪表身份仅用于本地关联数据，不是认证凭证。
    public var dashboardBLEIdentifier: UUID?
    public var dashboardSerialNumber: String?
    public var dashboardMaintenanceDistanceKm: Int?
    public var dashboardMaintenanceFlag: Int?
    public var lastDashboardSyncAt: Date?
    public var maintenanceWarningDistanceKm: Double?
    public var tankCapacityLiters: Double?
    public var reserveFuelPercent: Int?
    public var preferredDiagnosticAddress: PTOBDiagnosticAddress?
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
        odometerSource: PTMotorcycleOdometerSource? = .manual,
        dashboardBLEIdentifier: UUID? = nil,
        dashboardSerialNumber: String? = nil,
        dashboardMaintenanceDistanceKm: Int? = nil,
        dashboardMaintenanceFlag: Int? = nil,
        lastDashboardSyncAt: Date? = nil,
        maintenanceWarningDistanceKm: Double? = nil,
        tankCapacityLiters: Double? = nil,
        reserveFuelPercent: Int? = nil,
        preferredDiagnosticAddress: PTOBDiagnosticAddress? = nil,
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
        self.odometerSource = odometerSource
        self.dashboardBLEIdentifier = dashboardBLEIdentifier
        self.dashboardSerialNumber = dashboardSerialNumber
        self.dashboardMaintenanceDistanceKm = dashboardMaintenanceDistanceKm
        self.dashboardMaintenanceFlag = dashboardMaintenanceFlag
        self.lastDashboardSyncAt = lastDashboardSyncAt
        self.maintenanceWarningDistanceKm = maintenanceWarningDistanceKm
        self.tankCapacityLiters = tankCapacityLiters
        self.reserveFuelPercent = reserveFuelPercent
        self.preferredDiagnosticAddress = preferredDiagnosticAddress
        self.maintenanceRecords = maintenanceRecords
        self.diagnosticReports = diagnosticReports
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// EN: Legacy automatic mock snapshots have no source field or hardware identity.
    /// ES: Las instantáneas simuladas antiguas no tienen origen ni identidad de hardware.
    /// 中文：旧版本自动保存的 mock 快照没有来源字段，也没有真实硬件身份。
    var isLegacyMockOdometer: Bool {
        odometerSource == nil
            && lastDashboardSyncAt != nil
            && dashboardBLEIdentifier == nil
            && dashboardSerialNumber == nil
    }

    public static var defaultXP400GT: PTMotorcycleProfile {
        PTMotorcycleProfile(
            name: "XP400 GT",
            brand: "Peugeot",
            model: "XP400 GT",
            tankCapacityLiters: 13.5,
            reserveFuelPercent: 10
        )
    }
}

// EN: A bounded dashboard sample keeps transport callbacks separate from garage persistence.
// ES: Una muestra limitada del tablero separa los callbacks de transporte de la persistencia del garaje.
// 中文：有边界的仪表快照将传输回调与车库存储隔离开。
/// EN: Describes whether a dashboard snapshot came from hardware or the local simulator.
/// ES: Describe si una instantánea procede del hardware o del simulador local.
/// 中文：描述仪表快照来自真实硬件还是本地模拟器。
public enum PTGarageDashboardSource: String, Codable, Sendable {
    case dashboard
    case mock
}

public struct PTGarageDashboardSnapshot: Equatable, Sendable {
    public let odometerKm: Double?
    public let maintenanceDistanceKm: Int?
    public let maintenanceFlag: Int?
    public let source: PTGarageDashboardSource
    public let capturedAt: Date

    public init(
        odometerKm: Double? = nil,
        maintenanceDistanceKm: Int? = nil,
        maintenanceFlag: Int? = nil,
        source: PTGarageDashboardSource = .dashboard,
        capturedAt: Date = Date()
    ) {
        self.odometerKm = odometerKm
        self.maintenanceDistanceKm = maintenanceDistanceKm
        self.maintenanceFlag = maintenanceFlag
        self.source = source
        self.capturedAt = capturedAt
    }

    public var hasAnyValue: Bool {
        odometerKm != nil || maintenanceDistanceKm != nil || maintenanceFlag != nil
    }
}

public enum PTGarageDashboardSyncResult: String, Equatable, Sendable {
    case updated
    case unchanged
    case unavailable
    case identityConflict
    case vehicleNotFound
}

public enum PTGarageDashboardIdentityResolution: Equatable, Sendable {
    case matched(UUID)
    case candidate(UUID)
    case conflict
    case unavailable
}

public struct PTMotorcycleGarageDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let selectedVehicleID: UUID?
    public let vehicles: [PTMotorcycleProfile]

    nonisolated public init(
        schemaVersion: Int = 4,
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
    public static let currentSchemaVersion = 4
    public static let defaultMaintenanceWarningDistanceKm = 2_500.0
    public static let maximumMaintenanceWarningDistanceKm = 65_535.0
    public static let maximumVehicleCount = 32
    public static let maximumMaintenanceCount = 100
    public static let maximumPartCount = 100
    public static let maximumDiagnosticReportCount = 30

    private let userDefaults: UserDefaults
    public private(set) var vehicles: [PTMotorcycleProfile]
    public private(set) var selectedVehicleID: UUID?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        var storedSchemaVersion = 0
        if let data = userDefaults.data(forKey: Self.storageKey),
           let document = try? JSONDecoder().decode(PTMotorcycleGarageDocument.self, from: data),
           !document.vehicles.isEmpty {
            storedSchemaVersion = document.schemaVersion
            self.vehicles = document.vehicles
            self.selectedVehicleID = document.selectedVehicleID
                ?? document.vehicles.first?.id
        } else {
            let defaultVehicle = PTMotorcycleProfile.defaultXP400GT
            self.vehicles = [defaultVehicle]
            self.selectedVehicleID = defaultVehicle.id
        }

        var shouldPersist = storedSchemaVersion < Self.currentSchemaVersion
        let legacyWarningDistance = Self.normalizedMaintenanceWarningDistance(
            PTMotoUserDefaultStruct.PTMotoSafteyMileValue
        ) ?? Self.defaultMaintenanceWarningDistanceKm
        for index in vehicles.indices {
            let currentValue = vehicles[index].maintenanceWarningDistanceKm
            let normalizedValue = Self.normalizedMaintenanceWarningDistance(currentValue)
                ?? legacyWarningDistance
            if currentValue != normalizedValue {
                vehicles[index].maintenanceWarningDistanceKm = normalizedValue
                shouldPersist = true
            }

            if vehicles[index].tankCapacityLiters == nil,
               Self.isXP400GT(vehicles[index]) {
                vehicles[index].tankCapacityLiters = 13.5
                vehicles[index].reserveFuelPercent = 10
                shouldPersist = true
            }
            let normalizedTankCapacity = Self.normalizedTankCapacity(vehicles[index].tankCapacityLiters)
            if vehicles[index].tankCapacityLiters != normalizedTankCapacity {
                vehicles[index].tankCapacityLiters = normalizedTankCapacity
                shouldPersist = true
            }
            let normalizedReserve = Self.normalizedReserve(vehicles[index].reserveFuelPercent)
            if vehicles[index].reserveFuelPercent != normalizedReserve {
                vehicles[index].reserveFuelPercent = normalizedReserve
                shouldPersist = true
            }
        }

        if selectedVehicleID == nil || !vehicles.contains(where: { $0.id == selectedVehicleID }) {
            selectedVehicleID = vehicles.first?.id
            shouldPersist = true
        }

        if shouldPersist {
            persist(notify: false)
        }
        syncLegacyWarningDistance()
    }

    public var currentVehicle: PTMotorcycleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first { $0.id == selectedVehicleID }
    }

    public func vehicle(id: UUID) -> PTMotorcycleProfile? {
        vehicles.first { $0.id == id }
    }

    /// EN: The selected vehicle's threshold is the canonical runtime value for legacy dashboard consumers.
    /// ES: El umbral del vehículo seleccionado es el valor de ejecución canónico para los consumidores antiguos del tablero.
    /// 中文：当前车辆的预警值是旧仪表页面运行时使用的统一值。
    public var currentMaintenanceWarningDistanceKm: Double {
        Self.normalizedMaintenanceWarningDistance(currentVehicle?.maintenanceWarningDistanceKm)
            ?? Self.defaultMaintenanceWarningDistanceKm
    }

    public func maintenanceWarningDistanceKm(for vehicleID: UUID) -> Double {
        Self.normalizedMaintenanceWarningDistance(vehicle(id: vehicleID)?.maintenanceWarningDistanceKm)
            ?? Self.defaultMaintenanceWarningDistanceKm
    }

    @discardableResult
    public func selectVehicle(id: UUID) -> Bool {
        guard vehicles.contains(where: { $0.id == id }) else { return false }
        guard selectedVehicleID != id else {
            syncLegacyWarningDistance()
            return true
        }
        selectedVehicleID = id
        syncLegacyWarningDistance()
        persist()
        return true
    }

    @discardableResult
    public func updateVehicleName(_ name: String, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedName = nonEmptyText(name) else {
            return false
        }
        guard vehicles[index].name != normalizedName else { return true }

        vehicles[index].name = normalizedName
        touchVehicle(at: index)
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
        odometerKm: Double = 0,
        tankCapacityLiters: Double? = nil,
        reserveFuelPercent: Int? = nil,
        preferredDiagnosticAddress: PTOBDiagnosticAddress? = nil
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
            maintenanceWarningDistanceKm: Self.defaultMaintenanceWarningDistanceKm,
            tankCapacityLiters: Self.normalizedTankCapacity(tankCapacityLiters)
                ?? (Self.isXP400GT(brand: brand, model: model) ? 13.5 : nil),
            reserveFuelPercent: Self.normalizedReserve(reserveFuelPercent)
                ?? (Self.isXP400GT(brand: brand, model: model) ? 10 : nil),
            preferredDiagnosticAddress: preferredDiagnosticAddress,
            createdAt: now,
            updatedAt: now
        )
        vehicles.append(profile)
        selectedVehicleID = profile.id
        syncLegacyWarningDistance()
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
        syncLegacyWarningDistance()
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
        vehicles[index].odometerSource = .manual
        touchVehicle(at: index)
        persist()
        return true
    }

    /// EN: Store the early-warning threshold in kilometers and mirror it to the legacy selected-vehicle setting.
    /// ES: Guarda el umbral de aviso anticipado en kilómetros y lo refleja en la configuración antigua del vehículo seleccionado.
    /// 中文：以公里保存提前预警值，并同步到旧的当前车辆设置。
    @discardableResult
    public func updateMaintenanceWarningDistance(
        _ distanceKm: Double,
        vehicleID: UUID? = nil
    ) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedDistance = Self.normalizedMaintenanceWarningDistance(distanceKm) else {
            return false
        }

        guard vehicles[index].maintenanceWarningDistanceKm != normalizedDistance else {
            if vehicles[index].id == selectedVehicleID {
                syncLegacyWarningDistance()
            }
            return true
        }

        vehicles[index].maintenanceWarningDistanceKm = normalizedDistance
        touchVehicle(at: index)
        if vehicles[index].id == selectedVehicleID {
            syncLegacyWarningDistance()
        }
        persist()
        return true
    }

    // EN: Fuel profile values are vehicle-owned and bounded so range estimates cannot explode from bad input.
    // ES: El perfil de combustible pertenece al vehículo y está limitado para evitar estimaciones descontroladas.
    // 中文：油耗配置归属于车辆并限制范围，避免错误输入导致续航估算失控。
    @discardableResult
    public func updateFuelProfile(
        tankCapacityLiters: Double?,
        reserveFuelPercent: Int?,
        vehicleID: UUID? = nil
    ) -> Bool {
        guard let index = indexOfVehicle(vehicleID) else { return false }
        let normalizedCapacity = Self.normalizedTankCapacity(tankCapacityLiters)
        let normalizedReserve = Self.normalizedReserve(reserveFuelPercent)
        guard tankCapacityLiters == nil || normalizedCapacity != nil,
              reserveFuelPercent == nil || normalizedReserve != nil else {
            return false
        }
        guard vehicles[index].tankCapacityLiters != normalizedCapacity
                || vehicles[index].reserveFuelPercent != normalizedReserve else {
            return true
        }
        vehicles[index].tankCapacityLiters = normalizedCapacity
        vehicles[index].reserveFuelPercent = normalizedReserve
        touchVehicle(at: index)
        persist()
        return true
    }

    @discardableResult
    public func updatePreferredDiagnosticAddress(
        _ address: PTOBDiagnosticAddress?,
        vehicleID: UUID? = nil
    ) -> Bool {
        guard let index = indexOfVehicle(vehicleID) else { return false }
        guard vehicles[index].preferredDiagnosticAddress != address else { return true }
        vehicles[index].preferredDiagnosticAddress = address
        touchVehicle(at: index)
        persist()
        return true
    }

    /// EN: Resolve a dashboard identity before any live sample is assigned to a vehicle.
    /// ES: Resuelve la identidad del tablero antes de asignar cualquier muestra a una motocicleta.
    /// 中文：在把实时数据分配给车辆前，先解析仪表身份。
    public func resolveDashboardIdentity(
        _ identity: PTDashboardConnectionIdentity,
        preferredVehicleID: UUID? = nil
    ) -> PTGarageDashboardIdentityResolution {
        let serial = Self.normalizedDashboardSerial(identity.reportedSerialNumber)
        let centralID = identity.centralIdentifier

        let serialMatches = vehicles.filter {
            guard let storedSerial = Self.normalizedDashboardSerial($0.dashboardSerialNumber) else { return false }
            return serial != nil && storedSerial == serial
        }
        let centralMatches = vehicles.filter {
            centralID != nil && $0.dashboardBLEIdentifier == centralID
        }

        if serialMatches.count > 1 || centralMatches.count > 1 {
            return .conflict
        }

        let serialVehicleID = serialMatches.first?.id
        let centralVehicleID = centralMatches.first?.id
        if let serialVehicleID, let centralVehicleID, serialVehicleID != centralVehicleID {
            return .conflict
        }
        if let matchedID = serialVehicleID ?? centralVehicleID {
            return .matched(matchedID)
        }

        if let preferredVehicleID,
           let preferredVehicle = vehicle(id: preferredVehicleID),
           preferredVehicle.dashboardBLEIdentifier == nil,
           Self.normalizedDashboardSerial(preferredVehicle.dashboardSerialNumber) == nil {
            return .candidate(preferredVehicleID)
        }

        return .unavailable
    }

    /// EN: Bind only unused identity values or the same vehicle's refreshed UUID alias.
    /// ES: Solo vincula identidades libres o un alias UUID actualizado de la misma motocicleta.
    /// 中文：只绑定未占用的身份，或更新同一车辆重新配对后的 UUID 别名。
    @discardableResult
    public func bindDashboardIdentity(
        _ identity: PTDashboardConnectionIdentity,
        to vehicleID: UUID
    ) -> Bool {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicleID }) else { return false }
        let serial = Self.normalizedDashboardSerial(identity.reportedSerialNumber)
        let centralID = identity.centralIdentifier

        for vehicle in vehicles where vehicle.id != vehicleID {
            if let serial,
               Self.normalizedDashboardSerial(vehicle.dashboardSerialNumber) == serial {
                return false
            }
            if let centralID, vehicle.dashboardBLEIdentifier == centralID {
                return false
            }
        }

        if let serial,
           let storedSerial = Self.normalizedDashboardSerial(vehicles[index].dashboardSerialNumber),
           storedSerial != serial {
            return false
        }

        var didChange = false
        if vehicles[index].dashboardBLEIdentifier != centralID, let centralID {
            vehicles[index].dashboardBLEIdentifier = centralID
            didChange = true
        }
        if vehicles[index].dashboardSerialNumber != serial, let serial {
            vehicles[index].dashboardSerialNumber = serial
            didChange = true
        }
        guard didChange else { return true }
        touchVehicle(at: index)
        persist()
        return true
    }

    /// EN: Explicit reassignment is used only after the user confirms a conflicting dashboard identity.
    /// ES: La reasignación explícita solo se usa después de que el usuario confirme una identidad conflictiva.
    /// 中文：只有用户确认仪表身份冲突后，才能执行显式重新关联。
    @discardableResult
    public func reassignDashboardIdentity(
        _ identity: PTDashboardConnectionIdentity,
        to vehicleID: UUID
    ) -> Bool {
        guard identity.isUsable,
              let targetIndex = vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            return false
        }

        let serial = Self.normalizedDashboardSerial(identity.reportedSerialNumber)
        let centralID = identity.centralIdentifier
        var didChange = false

        for index in vehicles.indices where index != targetIndex {
            let ownsSerial = serial != nil
                && Self.normalizedDashboardSerial(vehicles[index].dashboardSerialNumber) == serial
            let ownsCentral = centralID != nil
                && vehicles[index].dashboardBLEIdentifier == centralID
            guard ownsSerial || ownsCentral else { continue }

            if ownsSerial {
                vehicles[index].dashboardSerialNumber = nil
            }
            if ownsCentral {
                vehicles[index].dashboardBLEIdentifier = nil
            }
            touchVehicle(at: index)
            didChange = true
        }

        if let centralID, vehicles[targetIndex].dashboardBLEIdentifier != centralID {
            vehicles[targetIndex].dashboardBLEIdentifier = centralID
            didChange = true
        }
        if let serial, vehicles[targetIndex].dashboardSerialNumber != serial {
            vehicles[targetIndex].dashboardSerialNumber = serial
            didChange = true
        }

        guard didChange else { return true }
        touchVehicle(at: targetIndex)
        persist()
        return true
    }

    /// EN: Apply a bounded dashboard snapshot atomically; mock data never replaces real/manual mileage, and hardware data stays monotonic.
    /// ES: Aplica una instantánea limitada del tablero; los datos simulados nunca reemplazan el kilometraje real/manual y el hardware mantiene la monotonía.
    /// 中文：原子应用有边界的仪表快照；模拟数据不能覆盖真实/手动里程，真实仪表数据仍保持单调递增。
    @discardableResult
    public func applyDashboardSnapshot(
        _ snapshot: PTGarageDashboardSnapshot,
        to vehicleID: UUID,
        recordReceiptWhenUnchanged: Bool = false
    ) -> PTGarageDashboardSyncResult {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicleID }) else {
            return .vehicleNotFound
        }

        let odometer = snapshot.odometerKm.flatMap(Self.normalizedOdometer)
        let maintenanceDistance = snapshot.maintenanceDistanceKm.flatMap(Self.normalizedDashboardMaintenanceDistance)
        let maintenanceFlag = snapshot.maintenanceFlag.flatMap(Self.normalizedDashboardMaintenanceFlag)
        guard odometer != nil || maintenanceDistance != nil || maintenanceFlag != nil else {
            return .unavailable
        }

        var didChange = false
        if let odometer {
            let currentOdometer = vehicles[index].odometerKm
            let currentSource = vehicles[index].odometerSource
            let isUsablePositiveSample = odometer > 0 || currentOdometer == 0
            let shouldAcceptOdometer: Bool

            switch snapshot.source {
            case .mock:
                shouldAcceptOdometer = currentOdometer == 0
                    || ((currentSource == .mock || vehicles[index].isLegacyMockOdometer)
                        && isUsablePositiveSample)
            case .dashboard:
                shouldAcceptOdometer = isUsablePositiveSample
                    && (currentSource == nil
                        || currentSource == .mock
                        || odometer >= currentOdometer)
            }

            if shouldAcceptOdometer {
                if currentOdometer != odometer {
                    vehicles[index].odometerKm = odometer
                    didChange = true
                }
                let nextSource: PTMotorcycleOdometerSource = snapshot.source == .mock ? .mock : .dashboard
                if vehicles[index].odometerSource != nextSource {
                    vehicles[index].odometerSource = nextSource
                    didChange = true
                }
            }
        }
        if let maintenanceDistance,
           vehicles[index].dashboardMaintenanceDistanceKm != maintenanceDistance {
            vehicles[index].dashboardMaintenanceDistanceKm = maintenanceDistance
            didChange = true
        }
        if let maintenanceFlag,
           vehicles[index].dashboardMaintenanceFlag != maintenanceFlag {
            vehicles[index].dashboardMaintenanceFlag = maintenanceFlag
            didChange = true
        }

        guard didChange || recordReceiptWhenUnchanged else { return .unchanged }
        vehicles[index].lastDashboardSyncAt = snapshot.capturedAt
        touchVehicle(at: index)
        persist()
        return .updated
    }

    /// EN: Explicitly sync a safe, monotonic odometer sample from the existing dashboard coordinator.
    /// ES: Sincroniza explícitamente una muestra de odómetro segura y monotónica desde el coordinador existente.
    /// 中文：从现有仪表协调器显式同步安全且不倒退的里程数据。
    @discardableResult
    public func syncCurrentVehicleFromLiveData() -> Bool {
        PTVehicleConnectivityCoordinator.shared.syncCurrentGarageVehicleNow() == .updated
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
            schemaVersion: Self.currentSchemaVersion,
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

    private static func normalizedOdometer(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= 2_000_000 else { return nil }
        return value
    }

    private func validOdometer(_ value: Double) -> Double? {
        Self.normalizedOdometer(value)
    }

    private func validOptionalOdometer(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return validOdometer(value)
    }

    private func validYear(_ value: Int?) -> Int? {
        guard let value, (1900...2200).contains(value) else { return nil }
        return value
    }

    private static func normalizedDashboardMaintenanceDistance(_ value: Int) -> Int? {
        guard (0...Int(UInt16.max)).contains(value) else { return nil }
        return value
    }

    private static func normalizedDashboardMaintenanceFlag(_ value: Int) -> Int? {
        guard (0...Int(UInt8.max)).contains(value) else { return nil }
        return value
    }

    private static func normalizedDashboardSerial(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .filter { $0.isASCII && !$0.isNewline && !$0.isWhitespace }
            .uppercased()
        return normalized.isEmpty ? nil : String(normalized.prefix(64))
    }

    private static func normalizedMaintenanceWarningDistance(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= 1,
              value <= maximumMaintenanceWarningDistanceKm else {
            return nil
        }
        return value.rounded()
    }

    private static func normalizedTankCapacity(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (1...50).contains(value) else { return nil }
        return value
    }

    private static func normalizedReserve(_ value: Int?) -> Int? {
        guard let value, (0...50).contains(value) else { return nil }
        return value
    }

    private static func isXP400GT(_ profile: PTMotorcycleProfile) -> Bool {
        isXP400GT(brand: profile.brand, model: profile.model)
    }

    private static func isXP400GT(brand: String, model: String) -> Bool {
        let value = "\(brand) \(model)".lowercased()
        return value.contains("peugeot") && value.contains("xp400")
    }

    private func syncLegacyWarningDistance() {
        PTMotoUserDefaultStruct.PTMotoSafteyMileValue = currentMaintenanceWarningDistanceKm
    }
}
