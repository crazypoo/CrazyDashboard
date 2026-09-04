//
//  PTMotorcycleGarage.swift
//  CrazyDashboard
//
//  EN: Small, main-actor-isolated garage storage for motorcycle-owned records.
//  ES: Almacenamiento pequeño y aislado en el actor principal para registros de cada motocicleta.
//  中文：面向每辆摩托车的小型主线程隔离档案存储。
//

import Foundation

nonisolated public struct PTGarageMaintenanceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let completedAt: Date
    public let mileageKm: Double
    public let nextDueMileageKm: Double?
    public let notes: String
    public let cost: Double?
    public let currency: String?
    public let dueDate: Date?
    public let associatedPartIDs: [UUID]
    public let updatedAt: Date

    nonisolated public init(
        id: UUID = UUID(),
        title: String,
        completedAt: Date = Date(),
        mileageKm: Double,
        nextDueMileageKm: Double? = nil,
        notes: String = "",
        cost: Double? = nil,
        currency: String? = nil,
        dueDate: Date? = nil,
        associatedPartIDs: [UUID] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.completedAt = completedAt
        self.mileageKm = mileageKm
        self.nextDueMileageKm = nextDueMileageKm
        self.notes = notes
        self.cost = cost
        self.currency = currency
        self.dueDate = dueDate
        self.associatedPartIDs = associatedPartIDs
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, completedAt, mileageKm, nextDueMileageKm, notes, cost, currency, dueDate, associatedPartIDs, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date()
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try container.decode(String.self, forKey: .title),
            completedAt: completedAt,
            mileageKm: try container.decodeIfPresent(Double.self, forKey: .mileageKm) ?? 0,
            nextDueMileageKm: try container.decodeIfPresent(Double.self, forKey: .nextDueMileageKm),
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            cost: try container.decodeIfPresent(Double.self, forKey: .cost),
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            dueDate: try container.decodeIfPresent(Date.self, forKey: .dueDate),
            associatedPartIDs: try container.decodeIfPresent([UUID].self, forKey: .associatedPartIDs) ?? [],
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? completedAt
        )
    }
}

// EN: This profile stores observations and setup values per motorcycle without pretending they are factory specifications.
// ES: Este perfil guarda observaciones y ajustes por motocicleta sin presentarlos como especificaciones de fábrica.
// 中文：该档案按车辆保存观察值和设定值，不把它们伪装成厂家规格。
nonisolated public struct PTGarageTireSuspensionProfile: Codable, Equatable, Sendable {
    public let frontTireBrand: String
    public let frontTireModel: String
    public let frontTireSize: String
    public let rearTireBrand: String
    public let rearTireModel: String
    public let rearTireSize: String
    public let coldFrontPressure: Double?
    public let coldRearPressure: Double?
    public let hotFrontPressure: Double?
    public let hotRearPressure: Double?
    public let pressureUnit: String
    public let loadScenario: String
    public let frontPreload: String
    public let frontRebound: String
    public let frontCompression: String
    public let rearPreload: String
    public let rearRebound: String
    public let rearCompression: String
    public let odometerKm: Double?
    public let notes: String
    public let updatedAt: Date

    public init(
        frontTireBrand: String = "",
        frontTireModel: String = "",
        frontTireSize: String = "",
        rearTireBrand: String = "",
        rearTireModel: String = "",
        rearTireSize: String = "",
        coldFrontPressure: Double? = nil,
        coldRearPressure: Double? = nil,
        hotFrontPressure: Double? = nil,
        hotRearPressure: Double? = nil,
        pressureUnit: String = "bar",
        loadScenario: String = "",
        frontPreload: String = "",
        frontRebound: String = "",
        frontCompression: String = "",
        rearPreload: String = "",
        rearRebound: String = "",
        rearCompression: String = "",
        odometerKm: Double? = nil,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.frontTireBrand = frontTireBrand
        self.frontTireModel = frontTireModel
        self.frontTireSize = frontTireSize
        self.rearTireBrand = rearTireBrand
        self.rearTireModel = rearTireModel
        self.rearTireSize = rearTireSize
        self.coldFrontPressure = Self.validPressure(coldFrontPressure)
        self.coldRearPressure = Self.validPressure(coldRearPressure)
        self.hotFrontPressure = Self.validPressure(hotFrontPressure)
        self.hotRearPressure = Self.validPressure(hotRearPressure)
        self.pressureUnit = pressureUnit.lowercased() == "psi" ? "psi" : (pressureUnit.lowercased() == "kpa" ? "kPa" : "bar")
        self.loadScenario = loadScenario
        self.frontPreload = frontPreload
        self.frontRebound = frontRebound
        self.frontCompression = frontCompression
        self.rearPreload = rearPreload
        self.rearRebound = rearRebound
        self.rearCompression = rearCompression
        self.odometerKm = Self.validOdometer(odometerKm)
        self.notes = notes
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case frontTireBrand, frontTireModel, frontTireSize
        case rearTireBrand, rearTireModel, rearTireSize
        case coldFrontPressure, coldRearPressure, hotFrontPressure, hotRearPressure
        case pressureUnit, loadScenario
        case frontPreload, frontRebound, frontCompression
        case rearPreload, rearRebound, rearCompression
        case odometerKm, notes, updatedAt
    }

    // EN: Decode every field optionally so profiles saved before Build 45 remain usable.
    // ES: Decodifica todos los campos como opcionales para conservar los perfiles guardados antes de Build 45.
    // 中文：所有字段都兼容缺失，确保 Build45 之前保存的档案仍可使用。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.init(
            frontTireBrand: try container.decodeIfPresent(String.self, forKey: .frontTireBrand) ?? "",
            frontTireModel: try container.decodeIfPresent(String.self, forKey: .frontTireModel) ?? "",
            frontTireSize: try container.decodeIfPresent(String.self, forKey: .frontTireSize) ?? "",
            rearTireBrand: try container.decodeIfPresent(String.self, forKey: .rearTireBrand) ?? "",
            rearTireModel: try container.decodeIfPresent(String.self, forKey: .rearTireModel) ?? "",
            rearTireSize: try container.decodeIfPresent(String.self, forKey: .rearTireSize) ?? "",
            coldFrontPressure: try container.decodeIfPresent(Double.self, forKey: .coldFrontPressure),
            coldRearPressure: try container.decodeIfPresent(Double.self, forKey: .coldRearPressure),
            hotFrontPressure: try container.decodeIfPresent(Double.self, forKey: .hotFrontPressure),
            hotRearPressure: try container.decodeIfPresent(Double.self, forKey: .hotRearPressure),
            pressureUnit: try container.decodeIfPresent(String.self, forKey: .pressureUnit) ?? "bar",
            loadScenario: try container.decodeIfPresent(String.self, forKey: .loadScenario) ?? "",
            frontPreload: try container.decodeIfPresent(String.self, forKey: .frontPreload) ?? "",
            frontRebound: try container.decodeIfPresent(String.self, forKey: .frontRebound) ?? "",
            frontCompression: try container.decodeIfPresent(String.self, forKey: .frontCompression) ?? "",
            rearPreload: try container.decodeIfPresent(String.self, forKey: .rearPreload) ?? "",
            rearRebound: try container.decodeIfPresent(String.self, forKey: .rearRebound) ?? "",
            rearCompression: try container.decodeIfPresent(String.self, forKey: .rearCompression) ?? "",
            odometerKm: try container.decodeIfPresent(Double.self, forKey: .odometerKm),
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            updatedAt: updatedAt
        )
    }

    private static func validPressure(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0.1...200).contains(value) else { return nil }
        return value
    }

    private static func validOdometer(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...2_000_000).contains(value) else { return nil }
        return value
    }
}

// EN: Refuel records are user-entered observations and never overwrite the dashboard odometer.
// ES: Los repostajes son observaciones introducidas por el usuario y nunca sobrescriben el odómetro del tablero.
// 中文：加油记录是用户输入的观察数据，绝不覆盖仪表原始里程。
nonisolated public struct PTGarageRefuelRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let odometerKm: Double
    public let liters: Double
    public let amount: Double?
    public let currency: String?
    public let isFullTank: Bool
    public let notes: String
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        odometerKm: Double,
        liters: Double,
        amount: Double? = nil,
        currency: String? = nil,
        isFullTank: Bool,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.liters = liters
        self.amount = amount
        self.currency = currency
        self.isFullTank = isFullTank
        self.notes = notes
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, odometerKm, liters, amount, currency, isFullTank, notes, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            date: date,
            odometerKm: try container.decodeIfPresent(Double.self, forKey: .odometerKm) ?? 0,
            liters: try container.decodeIfPresent(Double.self, forKey: .liters) ?? 0,
            amount: try container.decodeIfPresent(Double.self, forKey: .amount),
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            isFullTank: try container.decodeIfPresent(Bool.self, forKey: .isFullTank) ?? false,
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
        )
    }
}

nonisolated public struct PTFuelEconomySample: Codable, Equatable, Sendable {
    public let litersPer100Km: Double
    public let distanceKm: Double
    public let sourceRecordIDs: [UUID]

    public init(litersPer100Km: Double, distanceKm: Double, sourceRecordIDs: [UUID]) {
        self.litersPer100Km = litersPer100Km
        self.distanceKm = distanceKm
        self.sourceRecordIDs = sourceRecordIDs
    }
}

// EN: Full-tank calibration accepts only monotonic and plausible samples, so mock data cannot contaminate range estimates.
// ES: La calibración de tanque lleno acepta solo muestras plausibles y monotónicas, evitando que el simulador contamine la autonomía.
// 中文：满箱校准只接受合理且单调递增的样本，避免 mock 数据污染续航估算。
nonisolated public enum PTFuelRangeCalculator {
    public static func samples(
        from records: [PTGarageRefuelRecord],
        maximumLitersPer100Km: ClosedRange<Double> = 1...20
    ) -> [PTFuelEconomySample] {
        // EN: Preserve entry chronology so a lower mock or rollback odometer cannot be sorted into a false sample.
        // ES: Conserva la cronología para que un odómetro menor, simulado o retrocedido no genere una muestra falsa al ordenarlo.
        // 中文：按记录时间保持真实顺序，避免把较低的 mock/回拨里程排序后伪造成有效样本。
        let ordered = records.sorted {
            if $0.date == $1.date {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.date < $1.date
        }
        guard !ordered.isEmpty else { return [] }

        var previousFullTank: PTGarageRefuelRecord?
        var samples: [PTFuelEconomySample] = []
        for record in ordered {
            guard record.odometerKm.isFinite,
                  record.odometerKm >= 0,
                  record.liters.isFinite,
                  record.liters > 0 else {
                previousFullTank = nil
                continue
            }

            guard record.isFullTank else {
                previousFullTank = nil
                continue
            }

            guard let previous = previousFullTank else {
                previousFullTank = record
                continue
            }

            let distance = record.odometerKm - previous.odometerKm
            guard distance >= 5 else {
                // EN: A rollback, duplicate or implausible distance breaks the full-tank chain.
                // ES: Un retroceso, duplicado o distancia inverosímil rompe la cadena de tanque lleno.
                // 中文：回拨、重复或不合理的里程会中断满箱样本链。
                previousFullTank = nil
                continue
            }

            let economy = record.liters / distance * 100
            guard maximumLitersPer100Km.contains(economy) else {
                previousFullTank = nil
                continue
            }

            samples.append(
                PTFuelEconomySample(
                    litersPer100Km: economy,
                    distanceKm: distance,
                    sourceRecordIDs: [previous.id, record.id]
                )
            )
            previousFullTank = record
        }

        return samples
    }

    public static func weightedConsumption(from records: [PTGarageRefuelRecord]) -> (litersPer100Km: Double, sampleCount: Int)? {
        let validSamples = samples(from: records)
        let totalDistance = validSamples.reduce(0) { $0 + $1.distanceKm }
        guard !validSamples.isEmpty, totalDistance > 0 else { return nil }
        let weighted = validSamples.reduce(0) { $0 + $1.litersPer100Km * $1.distanceKm } / totalDistance
        return (weighted, validSamples.count)
    }

    public static func estimatedRange(
        fuelLevelPercent: Int,
        tankCapacityLiters: Double,
        reservePercent: Int,
        records: [PTGarageRefuelRecord]
    ) -> Double? {
        guard (0...100).contains(fuelLevelPercent), tankCapacityLiters > 0 else { return nil }
        let consumption = weightedConsumption(from: records)?.litersPer100Km
        guard let consumption, consumption > 0 else { return nil }
        let usablePercent = max(0, fuelLevelPercent - min(max(reservePercent, 0), 100))
        return tankCapacityLiters * Double(usablePercent) / 100 / consumption * 100
    }
}

nonisolated public struct PTGaragePartRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let partNumber: String
    public let installedAt: Date
    public let mileageKm: Double?
    public let notes: String
    public let updatedAt: Date

    nonisolated public init(
        id: UUID = UUID(),
        name: String,
        partNumber: String = "",
        installedAt: Date = Date(),
        mileageKm: Double? = nil,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.partNumber = partNumber
        self.installedAt = installedAt
        self.mileageKm = mileageKm
        self.notes = notes
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, partNumber, installedAt, mileageKm, notes, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt) ?? Date()
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decode(String.self, forKey: .name),
            partNumber: try container.decodeIfPresent(String.self, forKey: .partNumber) ?? "",
            installedAt: installedAt,
            mileageKm: try container.decodeIfPresent(Double.self, forKey: .mileageKm),
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? installedAt
        )
    }
}

/// EN: Persist only the read-only diagnostic evidence needed for a vehicle history.
/// ES: Solo conserva la evidencia de diagnóstico de solo lectura necesaria para el historial del vehículo.
/// 中文：只保存车辆历史所需的只读诊断证据。
nonisolated public struct PTGarageDIDRecord: Codable, Equatable, Sendable {
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

nonisolated public struct PTGarageDiagnosticReport: Codable, Equatable, Identifiable, Sendable {
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
nonisolated public enum PTMotorcycleOdometerSource: String, Codable, Sendable {
    case manual
    case dashboard
    case mock
}

nonisolated public struct PTMotorcycleProfile: Codable, Equatable, Identifiable, Sendable {
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
    public var tireSuspensionProfile: PTGarageTireSuspensionProfile?
    public var refuelRecords: [PTGarageRefuelRecord]?
    public var deletedRefuelIDs: [String: Date]?
    public var maintenanceRecords: [PTGarageMaintenanceRecord]
    public var deletedMaintenanceIDs: [String: Date]?
    public var diagnosticReports: [PTGarageDiagnosticReport]
    public var parts: [PTGaragePartRecord]
    public var deletedPartIDs: [String: Date]?
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
        tireSuspensionProfile: PTGarageTireSuspensionProfile? = nil,
        refuelRecords: [PTGarageRefuelRecord]? = nil,
        deletedRefuelIDs: [String: Date]? = nil,
        maintenanceRecords: [PTGarageMaintenanceRecord] = [],
        deletedMaintenanceIDs: [String: Date]? = nil,
        diagnosticReports: [PTGarageDiagnosticReport] = [],
        parts: [PTGaragePartRecord] = [],
        deletedPartIDs: [String: Date]? = nil,
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
        self.tireSuspensionProfile = tireSuspensionProfile
        self.refuelRecords = refuelRecords
        self.deletedRefuelIDs = deletedRefuelIDs
        self.maintenanceRecords = maintenanceRecords
        self.deletedMaintenanceIDs = deletedMaintenanceIDs
        self.diagnosticReports = diagnosticReports
        self.parts = parts
        self.deletedPartIDs = deletedPartIDs
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
nonisolated public enum PTGarageDashboardSource: String, Codable, Sendable {
    case dashboard
    case mock
}

nonisolated public struct PTGarageDashboardSnapshot: Equatable, Sendable {
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

nonisolated public enum PTGarageDashboardSyncResult: String, Equatable, Sendable {
    case updated
    case unchanged
    case unavailable
    case identityConflict
    case vehicleNotFound
}

nonisolated public enum PTGarageDashboardIdentityResolution: Equatable, Sendable {
    case matched(UUID)
    case candidate(UUID)
    case conflict
    case unavailable
}

nonisolated public struct PTMotorcycleGarageDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let selectedVehicleID: UUID?
    public let vehicles: [PTMotorcycleProfile]
    public let deletedVehicleIDs: [String: Date]?

    nonisolated public init(
        schemaVersion: Int = 6,
        selectedVehicleID: UUID? = nil,
        vehicles: [PTMotorcycleProfile] = [],
        deletedVehicleIDs: [String: Date]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.selectedVehicleID = selectedVehicleID
        self.vehicles = vehicles
        self.deletedVehicleIDs = deletedVehicleIDs
    }
}

// EN: Cloud records contain vehicle business data but intentionally omit local Bluetooth binding metadata.
// ES: Los registros en la nube contienen datos del vehículo, pero omiten deliberadamente la vinculación Bluetooth local.
// 中文：云端记录只包含车辆业务数据，刻意排除本机 Bluetooth 绑定信息。
nonisolated public struct PTGarageCloudVehicle: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let brand: String
    public let model: String
    public let year: Int?
    public let vin: String
    public let odometerKm: Double
    public let odometerSource: PTMotorcycleOdometerSource?
    public let maintenanceWarningDistanceKm: Double?
    public let tankCapacityLiters: Double?
    public let reserveFuelPercent: Int?
    public let tireSuspensionProfile: PTGarageTireSuspensionProfile?
    public let refuelRecords: [PTGarageRefuelRecord]
    public let deletedRefuelIDs: [String: Date]?
    public let maintenanceRecords: [PTGarageMaintenanceRecord]
    public let deletedMaintenanceIDs: [String: Date]?
    public let diagnosticReports: [PTGarageDiagnosticReport]
    public let parts: [PTGaragePartRecord]
    public let deletedPartIDs: [String: Date]?
    public let createdAt: Date
    public let updatedAt: Date

    nonisolated public init(
        id: UUID,
        name: String,
        brand: String,
        model: String,
        year: Int?,
        vin: String,
        odometerKm: Double,
        odometerSource: PTMotorcycleOdometerSource?,
        maintenanceWarningDistanceKm: Double?,
        tankCapacityLiters: Double?,
        reserveFuelPercent: Int?,
        tireSuspensionProfile: PTGarageTireSuspensionProfile?,
        refuelRecords: [PTGarageRefuelRecord],
        deletedRefuelIDs: [String: Date]?,
        maintenanceRecords: [PTGarageMaintenanceRecord],
        deletedMaintenanceIDs: [String: Date]?,
        diagnosticReports: [PTGarageDiagnosticReport],
        parts: [PTGaragePartRecord],
        deletedPartIDs: [String: Date]?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.model = model
        self.year = year
        self.vin = vin
        self.odometerKm = odometerKm
        self.odometerSource = odometerSource
        self.maintenanceWarningDistanceKm = maintenanceWarningDistanceKm
        self.tankCapacityLiters = tankCapacityLiters
        self.reserveFuelPercent = reserveFuelPercent
        self.tireSuspensionProfile = tireSuspensionProfile
        self.refuelRecords = refuelRecords
        self.deletedRefuelIDs = deletedRefuelIDs
        self.maintenanceRecords = maintenanceRecords
        self.deletedMaintenanceIDs = deletedMaintenanceIDs
        self.diagnosticReports = diagnosticReports
        self.parts = parts
        self.deletedPartIDs = deletedPartIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated public init(profile: PTMotorcycleProfile) {
        id = profile.id
        name = profile.name
        brand = profile.brand
        model = profile.model
        year = profile.year
        vin = profile.vin
        odometerKm = profile.odometerKm
        odometerSource = profile.odometerSource
        maintenanceWarningDistanceKm = profile.maintenanceWarningDistanceKm
        tankCapacityLiters = profile.tankCapacityLiters
        reserveFuelPercent = profile.reserveFuelPercent
        tireSuspensionProfile = profile.tireSuspensionProfile
        refuelRecords = profile.refuelRecords ?? []
        deletedRefuelIDs = profile.deletedRefuelIDs
        maintenanceRecords = profile.maintenanceRecords
        deletedMaintenanceIDs = profile.deletedMaintenanceIDs
        diagnosticReports = profile.diagnosticReports
        parts = profile.parts
        deletedPartIDs = profile.deletedPartIDs
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }

    nonisolated public func applying(to local: PTMotorcycleProfile?) -> PTMotorcycleProfile {
        PTMotorcycleProfile(
            id: id,
            name: name,
            brand: brand,
            model: model,
            year: year,
            vin: vin,
            odometerKm: odometerKm,
            odometerSource: odometerSource,
            dashboardBLEIdentifier: local?.dashboardBLEIdentifier,
            dashboardSerialNumber: local?.dashboardSerialNumber,
            dashboardMaintenanceDistanceKm: local?.dashboardMaintenanceDistanceKm,
            dashboardMaintenanceFlag: local?.dashboardMaintenanceFlag,
            lastDashboardSyncAt: local?.lastDashboardSyncAt,
            maintenanceWarningDistanceKm: maintenanceWarningDistanceKm,
            tankCapacityLiters: tankCapacityLiters,
            reserveFuelPercent: reserveFuelPercent,
            preferredDiagnosticAddress: local?.preferredDiagnosticAddress,
            tireSuspensionProfile: tireSuspensionProfile,
            refuelRecords: refuelRecords,
            deletedRefuelIDs: deletedRefuelIDs,
            maintenanceRecords: maintenanceRecords,
            deletedMaintenanceIDs: deletedMaintenanceIDs,
            diagnosticReports: diagnosticReports,
            parts: parts,
            deletedPartIDs: deletedPartIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated public struct PTGarageCloudDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let selectedVehicleID: UUID?
    public let vehicles: [PTGarageCloudVehicle]
    public let deletedVehicleIDs: [String: Date]
    public let modifiedAt: Date

    nonisolated public init(
        schemaVersion: Int = currentSchemaVersion,
        selectedVehicleID: UUID?,
        vehicles: [PTGarageCloudVehicle],
        deletedVehicleIDs: [String: Date] = [:],
        modifiedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.selectedVehicleID = selectedVehicleID
        self.vehicles = vehicles
        self.deletedVehicleIDs = deletedVehicleIDs
        self.modifiedAt = modifiedAt
    }

    nonisolated public init(local document: PTMotorcycleGarageDocument) {
        self.init(
            selectedVehicleID: document.selectedVehicleID,
            vehicles: document.vehicles.map(PTGarageCloudVehicle.init(profile:)),
            deletedVehicleIDs: document.deletedVehicleIDs ?? [:]
        )
    }

    nonisolated public static func merge(_ local: Self, _ remote: Self?) -> Self {
        guard let remote else { return local }
        var mergedByID = Dictionary(uniqueKeysWithValues: local.vehicles.map { ($0.id, $0) })
        for remoteVehicle in remote.vehicles {
            if let localVehicle = mergedByID[remoteVehicle.id] {
                mergedByID[remoteVehicle.id] = mergeVehicles(localVehicle, remoteVehicle)
            } else {
                mergedByID[remoteVehicle.id] = remoteVehicle
            }
        }

        var tombstones = local.deletedVehicleIDs
        for (id, date) in remote.deletedVehicleIDs {
            if date > (tombstones[id] ?? .distantPast) {
                tombstones[id] = date
            }
        }
        let visibleVehicles = mergedByID.values
            .filter { vehicle in
                tombstones[vehicle.id.uuidString] == nil
            }
            .sorted { $0.createdAt < $1.createdAt }
        let preferredSelection = local.selectedVehicleID.flatMap { id in
            visibleVehicles.contains(where: { $0.id == id }) ? id : nil
        } ?? remote.selectedVehicleID.flatMap { id in
            visibleVehicles.contains(where: { $0.id == id }) ? id : nil
        } ?? visibleVehicles.first?.id
        return Self(
            selectedVehicleID: preferredSelection,
            vehicles: visibleVehicles,
            deletedVehicleIDs: tombstones,
            modifiedAt: max(local.modifiedAt, remote.modifiedAt)
        )
    }

    // EN: Merge vehicle-owned records independently so one device cannot erase another device's unrelated edit.
    // ES: Combina los registros propios del vehículo por separado para que una edición no borre otra edición independiente.
    // 中文：按车辆子记录分别合并，避免一台设备的无关更新抹掉另一台设备的修改。
    private nonisolated static func mergeVehicles(
        _ local: PTGarageCloudVehicle,
        _ remote: PTGarageCloudVehicle
    ) -> PTGarageCloudVehicle {
        let scalarSource = remote.updatedAt > local.updatedAt ? remote : local
        let refuelTombstones = mergeTombstones(local.deletedRefuelIDs, remote.deletedRefuelIDs)
        let maintenanceTombstones = mergeTombstones(local.deletedMaintenanceIDs, remote.deletedMaintenanceIDs)
        let partTombstones = mergeTombstones(local.deletedPartIDs, remote.deletedPartIDs)
        return PTGarageCloudVehicle(
            id: scalarSource.id,
            name: scalarSource.name,
            brand: scalarSource.brand,
            model: scalarSource.model,
            year: scalarSource.year,
            vin: scalarSource.vin,
            odometerKm: scalarSource.odometerKm,
            odometerSource: scalarSource.odometerSource,
            maintenanceWarningDistanceKm: scalarSource.maintenanceWarningDistanceKm,
            tankCapacityLiters: scalarSource.tankCapacityLiters,
            reserveFuelPercent: scalarSource.reserveFuelPercent,
            tireSuspensionProfile: newerTireProfile(local.tireSuspensionProfile, remote.tireSuspensionProfile),
            refuelRecords: mergeRecords(
                local.refuelRecords,
                remote.refuelRecords,
                tombstones: refuelTombstones,
                id: \.id,
                updatedAt: \.updatedAt
            ),
            deletedRefuelIDs: refuelTombstones.isEmpty ? nil : refuelTombstones,
            maintenanceRecords: mergeRecords(
                local.maintenanceRecords,
                remote.maintenanceRecords,
                tombstones: maintenanceTombstones,
                id: \.id,
                updatedAt: \.updatedAt
            ),
            deletedMaintenanceIDs: maintenanceTombstones.isEmpty ? nil : maintenanceTombstones,
            diagnosticReports: newerRecords(local.diagnosticReports, remote.diagnosticReports),
            parts: mergeRecords(
                local.parts,
                remote.parts,
                tombstones: partTombstones,
                id: \.id,
                updatedAt: \.updatedAt
            ),
            deletedPartIDs: partTombstones.isEmpty ? nil : partTombstones,
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private nonisolated static func mergeTombstones(
        _ local: [String: Date]?,
        _ remote: [String: Date]?
    ) -> [String: Date] {
        var result = local ?? [:]
        for (id, date) in remote ?? [:] where date > (result[id] ?? .distantPast) {
            result[id] = date
        }
        return result
    }

    private nonisolated static func newerTireProfile(
        _ local: PTGarageTireSuspensionProfile?,
        _ remote: PTGarageTireSuspensionProfile?
    ) -> PTGarageTireSuspensionProfile? {
        switch (local, remote) {
        case (nil, let remote): return remote
        case (let local, nil): return local
        case let (.some(local), .some(remote)):
            return remote.updatedAt > local.updatedAt ? remote : local
        }
    }

    private nonisolated static func mergeRecords<Record>(
        _ local: [Record],
        _ remote: [Record],
        tombstones: [String: Date],
        id: (Record) -> UUID,
        updatedAt: (Record) -> Date
    ) -> [Record] {
        var records = Dictionary(uniqueKeysWithValues: local.map { (id($0), $0) })
        for record in remote {
            let recordID = id(record)
            if let existing = records[recordID] {
                if updatedAt(record) > updatedAt(existing) {
                    records[recordID] = record
                }
            } else {
                records[recordID] = record
            }
        }
        return records.values
            .filter { record in
                tombstones[id(record).uuidString] == nil
            }
            .sorted {
                if updatedAt($0) == updatedAt($1) {
                    return id($0).uuidString < id($1).uuidString
                }
                return updatedAt($0) > updatedAt($1)
            }
    }

    private nonisolated static func newerRecords<Record: Identifiable>(
        _ local: [Record],
        _ remote: [Record]
    ) -> [Record] where Record.ID: Hashable {
        var records = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for record in remote where records[record.id] == nil {
            records[record.id] = record
        }
        return Array(records.values)
    }
}

public struct PTGarageCloudSyncResult: Sendable {
    public let document: PTGarageCloudDocument
    public let didReadCloud: Bool
    public let didWriteCloud: Bool
    public let cloudErrorDescription: String?
}

// EN: The cloud actor serializes garage merges and makes offline edits safe to retry.
// ES: El actor de nube serializa las fusiones del garaje y permite reintentar ediciones sin conexión de forma segura.
// 中文：云端 actor 串行处理车库合并，让离线编辑可以安全重试。
public actor PTMotorcycleGarageCloudSyncService {
    public static let shared = PTMotorcycleGarageCloudSyncService()
    public static let fileName = "PTMotorcycleGarageCloud.json"

    public func synchronize(local: PTGarageCloudDocument) async -> PTGarageCloudSyncResult {
        var remote: PTGarageCloudDocument?
        var didReadCloud = false
        do {
            let data = try await PTDataPersistenceActor.shared.readCloudData(fileName: Self.fileName)
            remote = try JSONDecoder.ptGarageDecoder.decode(PTGarageCloudDocument.self, from: data)
            didReadCloud = true
        } catch {
            remote = nil
        }

        let merged = PTGarageCloudDocument.merge(local, remote)
        do {
            let data = try JSONEncoder.ptGarageEncoder.encode(merged)
            let result = try await PTDataPersistenceActor.shared.writeData(
                data,
                fileName: Self.fileName,
                syncToICloud: true
            )
            return PTGarageCloudSyncResult(
                document: merged,
                didReadCloud: didReadCloud,
                didWriteCloud: result.didWriteCloud,
                cloudErrorDescription: result.cloudErrorDescription
            )
        } catch {
            return PTGarageCloudSyncResult(
                document: merged,
                didReadCloud: didReadCloud,
                didWriteCloud: false,
                cloudErrorDescription: error.localizedDescription
            )
        }
    }
}

private extension JSONEncoder {
    nonisolated static var ptGarageEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var ptGarageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
    public static let currentSchemaVersion = 6
    public static let defaultMaintenanceWarningDistanceKm = 2_500.0
    public static let maximumMaintenanceWarningDistanceKm = 65_535.0
    public static let maximumVehicleCount = 32
    public static let maximumMaintenanceCount = 100
    public static let maximumPartCount = 100
    public static let maximumDiagnosticReportCount = 30

    private let userDefaults: UserDefaults
    public private(set) var vehicles: [PTMotorcycleProfile]
    public private(set) var selectedVehicleID: UUID?
    private var deletedVehicleIDs: [String: Date]
    private var cloudSyncTask: Task<Void, Never>?

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
            self.deletedVehicleIDs = document.deletedVehicleIDs ?? [:]
        } else {
            let defaultVehicle = PTMotorcycleProfile.defaultXP400GT
            self.vehicles = [defaultVehicle]
            self.selectedVehicleID = defaultVehicle.id
            self.deletedVehicleIDs = [:]
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
            persist(notify: false, scheduleCloud: false)
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
        deletedVehicleIDs[id.uuidString] = Date()
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

    // EN: Save tire, pressure and suspension observations on the selected motorcycle only.
    // ES: Guarda observaciones de neumáticos, presión y suspensión únicamente en la motocicleta seleccionada.
    // 中文：只把轮胎、胎压和悬挂观察值保存到当前车辆。
    @discardableResult
    public func updateTireSuspensionProfile(
        _ profile: PTGarageTireSuspensionProfile?,
        vehicleID: UUID? = nil
    ) -> Bool {
        guard let index = indexOfVehicle(vehicleID) else { return false }
        guard vehicles[index].tireSuspensionProfile != profile else { return true }
        vehicles[index].tireSuspensionProfile = profile
        touchVehicle(at: index)
        persist()
        return true
    }

    // EN: Add a bounded refuel observation without changing the authoritative odometer value.
    // ES: Añade una observación de repostaje limitada sin cambiar el odómetro autorizado.
    // 中文：增加有边界的加油观察记录，不改变权威里程值。
    @discardableResult
    public func addRefuel(
        date: Date = Date(),
        odometerKm: Double,
        liters: Double,
        amount: Double? = nil,
        currency: String? = nil,
        isFullTank: Bool,
        notes: String = "",
        vehicleID: UUID? = nil
    ) -> PTGarageRefuelRecord? {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedOdometer = validOdometer(odometerKm),
              liters.isFinite,
              liters > 0,
              liters <= 100,
              amount == nil || (amount?.isFinite == true && amount! >= 0) else {
            return nil
        }

        let normalizedCurrency = normalizeText(currency ?? "")
        let record = PTGarageRefuelRecord(
            date: date,
            odometerKm: normalizedOdometer,
            liters: liters,
            amount: amount,
            currency: normalizedCurrency.isEmpty ? nil : normalizedCurrency,
            isFullTank: isFullTank,
            notes: normalizeText(notes)
        )
        var records = vehicles[index].refuelRecords ?? []
        records.insert(record, at: 0)
        vehicles[index].refuelRecords = Array(records.prefix(200))
        touchVehicle(at: index)
        persist()
        return record
    }

    @discardableResult
    public func removeRefuel(id: UUID, vehicleID: UUID? = nil) -> Bool {
        guard let index = indexOfVehicle(vehicleID),
              var records = vehicles[index].refuelRecords,
              let recordIndex = records.firstIndex(where: { $0.id == id }) else {
            return false
        }
        records.remove(at: recordIndex)
        vehicles[index].refuelRecords = records
        var tombstones = vehicles[index].deletedRefuelIDs ?? [:]
        tombstones[id.uuidString] = max(tombstones[id.uuidString] ?? .distantPast, Date())
        vehicles[index].deletedRefuelIDs = tombstones
        touchVehicle(at: index)
        persist()
        return true
    }

    public func fuelEconomy(vehicleID: UUID? = nil) -> (litersPer100Km: Double, sampleCount: Int)? {
        guard let resolvedVehicleID = vehicleID ?? selectedVehicleID,
              let vehicle = vehicle(id: resolvedVehicleID) else {
            return nil
        }
        return PTFuelRangeCalculator.weightedConsumption(from: vehicle.refuelRecords ?? [])
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
        cost: Double? = nil,
        currency: String? = nil,
        dueDate: Date? = nil,
        associatedPartIDs: [UUID] = [],
        vehicleID: UUID? = nil
    ) -> PTGarageMaintenanceRecord? {
        guard let index = indexOfVehicle(vehicleID),
              let normalizedTitle = nonEmptyText(title),
              let normalizedMileage = validOdometer(mileageKm ?? vehicles[index].odometerKm),
              validOptionalOdometer(nextDueMileageKm) != nil || nextDueMileageKm == nil,
              cost == nil || (cost?.isFinite == true && cost! >= 0) else {
            return nil
        }

        let normalizedCurrency = normalizeText(currency ?? "")
        let availablePartIDs = Set(vehicles[index].parts.map(\.id))
        var normalizedPartIDs: [UUID] = []
        for partID in associatedPartIDs where availablePartIDs.contains(partID) && !normalizedPartIDs.contains(partID) {
            normalizedPartIDs.append(partID)
        }
        let record = PTGarageMaintenanceRecord(
            title: normalizedTitle,
            completedAt: completedAt,
            mileageKm: normalizedMileage,
            nextDueMileageKm: validOptionalOdometer(nextDueMileageKm),
            notes: normalizeText(notes),
            cost: cost,
            currency: normalizedCurrency.isEmpty ? nil : normalizedCurrency,
            dueDate: dueDate,
            associatedPartIDs: normalizedPartIDs
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
        var tombstones = vehicles[index].deletedMaintenanceIDs ?? [:]
        tombstones[id.uuidString] = max(tombstones[id.uuidString] ?? .distantPast, Date())
        vehicles[index].deletedMaintenanceIDs = tombstones
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
        var tombstones = vehicles[index].deletedPartIDs ?? [:]
        tombstones[id.uuidString] = max(tombstones[id.uuidString] ?? .distantPast, Date())
        vehicles[index].deletedPartIDs = tombstones
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

    // EN: Local persistence stays synchronous for UIKit; cloud synchronization is debounced and off the main thread.
    // ES: La persistencia local sigue siendo síncrona para UIKit; la nube se sincroniza con debounce fuera del hilo principal.
    // 中文：本地保存继续同步提供给 UIKit，云端同步采用防抖并在主线程之外执行。
    private func persist(notify: Bool = true, scheduleCloud: Bool = true) {
        let document = PTMotorcycleGarageDocument(
            schemaVersion: Self.currentSchemaVersion,
            selectedVehicleID: selectedVehicleID,
            vehicles: vehicles,
            deletedVehicleIDs: deletedVehicleIDs
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
        if scheduleCloud {
            scheduleCloudSync(document)
        }
        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    // EN: Sync keeps local hardware bindings private and only uploads the business archive.
    // ES: La sincronización mantiene privadas las vinculaciones de hardware y solo sube el archivo de negocio.
    // 中文：同步只上传业务档案，本机硬件绑定信息始终留在本机。
    public func syncGarageToICloud() {
        let document = PTMotorcycleGarageDocument(
            schemaVersion: Self.currentSchemaVersion,
            selectedVehicleID: selectedVehicleID,
            vehicles: vehicles,
            deletedVehicleIDs: deletedVehicleIDs
        )
        scheduleCloudSync(document)
    }

    // EN: Pulling cloud changes is explicit so a delayed network result never silently replaces an active UI edit.
    // ES: La descarga de cambios es explícita para que una respuesta tardía nunca reemplace silenciosamente una edición activa.
    // 中文：云端合并采用显式触发，避免延迟网络结果静默覆盖用户正在编辑的内容。
    @discardableResult
    public func refreshGarageFromICloud() async -> Bool {
        let localDocument = PTMotorcycleGarageDocument(
            schemaVersion: Self.currentSchemaVersion,
            selectedVehicleID: selectedVehicleID,
            vehicles: vehicles,
            deletedVehicleIDs: deletedVehicleIDs
        )
        let result = await PTMotorcycleGarageCloudSyncService.shared.synchronize(
            local: PTGarageCloudDocument(local: localDocument)
        )
        guard result.didReadCloud else { return false }
        applyCloudDocument(result.document)
        return true
    }

    private func scheduleCloudSync(_ document: PTMotorcycleGarageDocument) {
        cloudSyncTask?.cancel()
        let cloudDocument = PTGarageCloudDocument(local: document)
        cloudSyncTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await PTMotorcycleGarageCloudSyncService.shared.synchronize(local: cloudDocument)
        }
    }

    private func applyCloudDocument(_ document: PTGarageCloudDocument) {
        let localByID = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        let mergedVehicles = document.vehicles.map { cloudVehicle in
            cloudVehicle.applying(to: localByID[cloudVehicle.id])
        }
        let cloudIDs = Set(mergedVehicles.map(\.id))
        let retainedLocalVehicles = vehicles.filter {
            !cloudIDs.contains($0.id) && document.deletedVehicleIDs[$0.id.uuidString] == nil
        }
        vehicles = Array((retainedLocalVehicles + mergedVehicles).prefix(Self.maximumVehicleCount))
        deletedVehicleIDs = document.deletedVehicleIDs
        selectedVehicleID = document.selectedVehicleID.flatMap { id in
            vehicles.contains(where: { $0.id == id }) ? id : nil
        } ?? vehicles.first?.id
        syncLegacyWarningDistance()
        persist(notify: true, scheduleCloud: false)
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
