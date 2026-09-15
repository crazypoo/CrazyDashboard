//
//  PTVehicleIdentityResolverBuild64.swift
//  CrazyDashboard
//
//  EN: Resolves XP400 electronic identity from explicit evidence and stored profiles only.
//  ES: Resuelve la identidad electrónica del XP400 únicamente desde evidencia explícita y perfiles guardados.
//  中文：只使用显式证据和存储档案解析 XP400 电子身份。
//

import Foundation

public nonisolated struct PTVehicleElectronicIdentityResolutionInput: Sendable {
    public let vehicleID: UUID?
    public let vehicleModel: String?
    public let storedProfile: [PTVehiclePassportField]
    public let storedAdapterProfile: [PTVehiclePassportField]
    public let evidence: [PTProtocolEvidenceRecord]
    public let existingECUs: [PTElectronicControlUnit]
    public let diagnosticAdapter: PTDiagnosticAdapterIdentity?
    public let now: Date

    public init(
        vehicleID: UUID? = nil,
        vehicleModel: String? = nil,
        storedProfile: [PTVehiclePassportField] = [],
        storedAdapterProfile: [PTVehiclePassportField] = [],
        storedPassport: PTVehiclePassport? = nil,
        evidence: [PTProtocolEvidenceRecord] = [],
        existingECUs: [PTElectronicControlUnit] = [],
        diagnosticAdapter: PTDiagnosticAdapterIdentity? = nil,
        now: Date = Date()
    ) {
        self.vehicleID = vehicleID ?? storedPassport?.vehicleID
        self.vehicleModel = vehicleModel
            ?? storedPassport?.field(for: PTVehicleIdentityFieldKey.vehicleModel.rawValue)?.value
        self.storedProfile = storedProfile.isEmpty ? (storedPassport?.vehicleFields ?? []) : storedProfile
        self.storedAdapterProfile = storedAdapterProfile.isEmpty ? (storedPassport?.adapterFields ?? []) : storedAdapterProfile
        self.evidence = evidence
        self.existingECUs = existingECUs
        self.diagnosticAdapter = diagnosticAdapter
        self.now = now
    }
}

nonisolated extension PTVehicleIdentityResolver {
    // EN: This overload is additive; the existing Passport resolver remains source-compatible.
    // ES: Esta sobrecarga es aditiva; el resolvedor Passport existente mantiene la compatibilidad.
    // 中文：这个重载只做增量扩展，旧 Passport 解析接口保持兼容。
    public static func resolve(
        _ input: PTVehicleElectronicIdentityResolutionInput
    ) -> PTVehicleElectronicIdentity {
        let candidates = EvidenceCandidate.from(records: input.evidence)
        let profile = ProfileCandidateIndex(
            vehicleFields: input.storedProfile,
            adapterFields: input.storedAdapterProfile
        )
        let ecuCandidates = candidates + EvidenceCandidate.from(ecus: input.existingECUs)
        let ecus = PTECURole.allCases.compactMap { role in
            makeECU(role: role, candidates: ecuCandidates, profile: profile, now: input.now, vehicleID: input.vehicleID, vehicleModel: input.vehicleModel)
        }

        let adapter = makeAdapter(
            candidates: candidates + EvidenceCandidate.from(adapter: input.diagnosticAdapter),
            profile: profile,
            now: input.now,
            vehicleID: input.vehicleID,
            vehicleModel: input.vehicleModel
        )

        let model = literalOrProfile(
            input.vehicleModel,
            key: .vehicleModel,
            profile: profile,
            now: input.now
        )
        let electronicReference = select(
            keys: [.electronicReference, .dashboardReference],
            candidates: ecuCandidates,
            profile: profile,
            now: input.now
        )
        let identityID = PTVehicleIdentityStableID.make(identitySeed(
            vehicleID: input.vehicleID,
            vehicleModel: model.value
        ))
        let topology = makeTopology(
            identityID: identityID,
            vehicleID: input.vehicleID,
            vehicleModel: model.value,
            ecus: ecus,
            adapter: adapter,
            generatedAt: input.now
        )
        let lastVerifiedAt = input.evidence
            .filter { isVehicleEvidence($0, vehicleID: input.vehicleID) }
            .map(\.timestamp)
            .max()

        return PTVehicleElectronicIdentity(
            id: identityID,
            vehicleID: input.vehicleID,
            vehicleModel: model,
            electronicReference: electronicReference,
            ecus: ecus,
            diagnosticAdapter: adapter,
            topology: topology,
            generatedAt: input.now,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    public static func resolveElectronicIdentity(
        _ input: PTVehicleElectronicIdentityResolutionInput
    ) -> PTVehicleElectronicIdentity {
        resolve(input)
    }

    // EN: The legacy Passport is a compatibility projection of the richer Build 64 identity.
    // ES: El Passport heredado es una proyección compatible de la identidad más rica de Build 64.
    // 中文：旧 Passport 是 Build 64 丰富身份模型的兼容投影。
    public static func makePassport(
        from identity: PTVehicleElectronicIdentity,
        at date: Date? = nil
    ) -> PTVehiclePassport {
        var vehicleFields: [PTVehiclePassportField] = [
            passportField(.vehicleModel, identity.vehicleModel),
            passportField(.electronicReference, identity.electronicReference)
        ]
        for ecu in identity.ecus {
            vehicleFields.append(contentsOf: passportFields(for: ecu, fallbackDate: identity.generatedAt))
        }

        var adapterFields: [PTVehiclePassportField] = []
        if let adapter = identity.diagnosticAdapter {
            adapterFields = [
                passportField(.adapterVendor, adapter.vendor),
                passportField(.adapterModel, adapter.model),
                passportField(.adapterFirmware, adapter.firmwareVersion),
                passportField(.adapterTransport, adapter.transport),
                passportField(.adapterBLEFingerprint, adapter.bleFingerprint),
                passportField(.adapterProtocolFingerprint, adapter.protocolFingerprint),
                passportField(.adapterOTACapability, adapter.supportsJieliOTA)
            ]
        }

        return PTVehiclePassport(
            generatedAt: date ?? identity.generatedAt,
            vehicleID: identity.vehicleID,
            vehicleFields: vehicleFields,
            adapterFields: adapterFields
        )
    }

    public static func diff(
        old: PTVehicleElectronicIdentity?,
        new: PTVehicleElectronicIdentity,
        at date: Date? = nil
    ) -> PTVehicleIdentityDiff {
        let oldFields = old.map(fields(for:)) ?? [:]
        let newFields = fields(for: new)
        let keys = Set(oldFields.keys).union(newFields.keys).sorted { $0.rawValue < $1.rawValue }
        let changes = keys.compactMap { key -> PTVehicleIdentityFieldDiff? in
            let before = oldFields[key]
            let after = newFields[key]
            guard before?.value != after?.value else { return nil }

            let kind: PTVehicleIdentityFieldChangeKind
            switch (before?.value, after?.value) {
            case (nil, .some): kind = .added
            case (.some, nil): kind = .removed
            case (.some, .some): kind = .changed
            case (nil, nil): return nil
            }
            return PTVehicleIdentityFieldDiff(
                id: PTVehicleIdentityStableID.make("identity-field-diff:\(key.rawValue):\(old?.id.uuidString ?? "none"):\(new.id.uuidString)"),
                key: key,
                kind: kind,
                oldValue: before?.value,
                newValue: after?.value,
                firstSeenAt: before?.updatedAt ?? after?.updatedAt,
                lastSeenAt: after?.updatedAt ?? before?.updatedAt,
                evidenceIDs: Array(Set((before?.evidenceIDs ?? []) + (after?.evidenceIDs ?? [])))
            )
        }
        let diffIDSeed = "identity-diff:\(old?.id.uuidString ?? "none"):\(new.id.uuidString):\(changes.map { $0.key.rawValue }.joined(separator: ","))"
        return PTVehicleIdentityDiff(
            id: PTVehicleIdentityStableID.make(diffIDSeed),
            vehicleID: new.vehicleID,
            oldIdentityID: old?.id,
            newIdentityID: new.id,
            generatedAt: date ?? new.generatedAt,
            changes: changes
        )
    }
}

// EN: The app-level builder exposes Build 64 without changing the existing Passport API or transport calls.
// ES: El constructor de la app expone Build 64 sin cambiar la API Passport ni las llamadas de transporte existentes.
// 中文：App 层构建器暴露 Build 64 能力，不改变旧 Passport API 或传输调用。
@MainActor
public extension PTVehiclePassportBuilder {
    static func buildElectronicIdentity(at date: Date = Date()) -> PTVehicleElectronicIdentity {
        let passport = build(at: date)
        return PTVehicleIdentityResolver.resolve(
            PTVehicleElectronicIdentityResolutionInput(
                vehicleID: passport.vehicleID,
                storedPassport: passport,
                evidence: PTProtocolEvidenceV2Store.shared.records,
                now: date
            )
        )
    }
}

private nonisolated extension PTVehicleIdentityResolver {
    struct EvidenceCandidate: Sendable {
        let key: PTVehicleIdentityFieldKey
        let value: String
        let source: PTProtocolEvidenceSource
        let confidence: Double
        let evidenceIDs: [UUID]
        let updatedAt: Date
        let tier: PTVehicleIdentityEvidenceTier

        static func from(records: [PTProtocolEvidenceRecord]) -> [EvidenceCandidate] {
            var result: [EvidenceCandidate] = []
            for record in records {
                guard record.kind == .identity || record.kind == .response || record.kind == .adapterIdentity || record.kind == .firmwareOTA else { continue }
                let pairs = tokenPairs(in: [record.value, record.note, record.request, record.response])
                let role = role(from: pairs, record: record)
                let tier = evidenceTier(for: record)
                result.append(contentsOf: pairs.compactMap { rawKey, rawValue -> EvidenceCandidate? in
                    guard let key = fieldKey(rawKey, role: role, record: record),
                          let value = normalized(rawValue) else { return nil }
                    return EvidenceCandidate(
                        key: key,
                        value: value,
                        source: record.source,
                        confidence: record.confidence,
                        evidenceIDs: [record.id],
                        updatedAt: record.timestamp,
                        tier: tier
                    )
                })

                if let role, let address = address(from: pairs, reference: record.reference) {
                    result.append(
                        EvidenceCandidate(
                            key: addressKey(for: role),
                            value: "\(address.tx)->\(address.rx)",
                            source: record.source,
                            confidence: record.confidence,
                            evidenceIDs: [record.id],
                            updatedAt: record.timestamp,
                            tier: tier
                        )
                    )
                }

                if record.domain == .ymobdFirmwareOTA || record.kind == .firmwareOTA {
                    result.append(
                        EvidenceCandidate(
                            key: .adapterOTACapability,
                            value: "true",
                            source: record.source,
                            confidence: record.confidence,
                            evidenceIDs: [record.id],
                            updatedAt: record.timestamp,
                            tier: tier
                        )
                    )
                }
            }
            return result
        }

        static func from(ecus: [PTElectronicControlUnit]) -> [EvidenceCandidate] {
            ecus.flatMap { ecu in
                var result: [EvidenceCandidate] = []
                if supportsReference(for: ecu.role) {
                    result.append(contentsOf: direct(ecu.reference, key: referenceKey(for: ecu.role)))
                }
                result.append(contentsOf: direct(ecu.hardwareVersion, key: hardwareKey(for: ecu.role)))
                result.append(contentsOf: direct(ecu.softwareVersion, key: softwareKey(for: ecu.role)))
                result.append(contentsOf: direct(ecu.bootVersion, key: bootKey(for: ecu.role)))
                if supportsCalibration(for: ecu.role) {
                    result.append(contentsOf: direct(ecu.calibrationID, key: calibrationKey(for: ecu.role)))
                }
                result.append(contentsOf: direct(ecu.serialNumber, key: serialKey(for: ecu.role)))
                if let address = ecu.diagnosticAddress {
                    result.append(
                        EvidenceCandidate(
                            key: addressKey(for: ecu.role),
                            value: "\(address.tx)->\(address.rx)",
                            source: ecu.hardwareVersion.source,
                            confidence: max(ecu.hardwareVersion.confidence, ecu.softwareVersion.confidence),
                            evidenceIDs: ecu.diagnosticAddressEvidenceIDs,
                            updatedAt: ecu.lastSeenAt ?? Date(),
                            tier: ecu.hardwareVersion.tier
                        )
                    )
                }
                return result
            }
        }

        static func from(adapter: PTDiagnosticAdapterIdentity?) -> [EvidenceCandidate] {
            guard let adapter else { return [] }
            var result: [EvidenceCandidate] = []
            result += direct(adapter.vendor, key: .adapterVendor)
            result += direct(adapter.model, key: .adapterModel)
            result += direct(adapter.firmwareVersion, key: .adapterFirmware)
            result += direct(adapter.transport, key: .adapterTransport)
            result += direct(adapter.bleFingerprint, key: .adapterBLEFingerprint)
            result += direct(adapter.protocolFingerprint, key: .adapterProtocolFingerprint)
            if let ota = adapter.supportsJieliOTA.value {
                result.append(
                    EvidenceCandidate(
                        key: .adapterOTACapability,
                        value: ota ? "true" : "false",
                        source: adapter.supportsJieliOTA.source,
                        confidence: adapter.supportsJieliOTA.confidence,
                        evidenceIDs: adapter.supportsJieliOTA.evidenceIDs,
                        updatedAt: adapter.supportsJieliOTA.updatedAt,
                        tier: adapter.supportsJieliOTA.tier
                    )
                )
            }
            return result
        }

        private static func direct(_ value: PTEvidenceBackedValue<String>, key: PTVehicleIdentityFieldKey) -> [EvidenceCandidate] {
            guard let string = normalized(value.value) else { return [] }
            return [EvidenceCandidate(
                key: key,
                value: string,
                source: value.source,
                confidence: value.confidence,
                evidenceIDs: value.evidenceIDs,
                updatedAt: value.updatedAt,
                tier: value.tier
            )]
        }
    }

    struct ProfileCandidateIndex: Sendable {
        let vehicle: [String: PTVehiclePassportField]
        let adapter: [String: PTVehiclePassportField]

        init(vehicleFields: [PTVehiclePassportField], adapterFields: [PTVehiclePassportField]) {
            self.vehicle = Dictionary(uniqueKeysWithValues: vehicleFields.map { ($0.key, $0) })
            self.adapter = Dictionary(uniqueKeysWithValues: adapterFields.map { ($0.key, $0) })
        }

        func field(for key: PTVehicleIdentityFieldKey) -> PTVehiclePassportField? {
            let dictionary = key.rawValue.hasPrefix("adapter.") ? adapter : vehicle
            return dictionary[key.rawValue]
        }
    }

    struct FieldSnapshot: Sendable {
        let value: String?
        let updatedAt: Date
        let evidenceIDs: [UUID]
    }

    static func makeECU(
        role: PTECURole,
        candidates: [EvidenceCandidate],
        profile: ProfileCandidateIndex,
        now: Date,
        vehicleID: UUID?,
        vehicleModel: String?
    ) -> PTElectronicControlUnit? {
        let addressCandidate = best(keys: [addressKey(for: role)], candidates: candidates, profile: profile)
        let address = addressCandidate.flatMap { parseAddress($0.value) }
        let reference = supportsReference(for: role)
            ? select(keys: [referenceKey(for: role)], candidates: candidates, profile: profile, now: now)
            : .unavailable(at: now)
        let hardware = select(keys: [hardwareKey(for: role)], candidates: candidates, profile: profile, now: now)
        let software = select(keys: [softwareKey(for: role)], candidates: candidates, profile: profile, now: now)
        let boot = select(keys: [bootKey(for: role)], candidates: candidates, profile: profile, now: now)
        let calibration = supportsCalibration(for: role)
            ? select(keys: [calibrationKey(for: role)], candidates: candidates, profile: profile, now: now)
            : .unavailable(at: now)
        let serial = select(keys: [serialKey(for: role)], candidates: candidates, profile: profile, now: now)
        guard reference.isAvailable || address != nil || hardware.isAvailable || software.isAvailable || boot.isAvailable
                || calibration.isAvailable || serial.isAvailable else { return nil }

        let idSeed = "ecu:\(vehicleID?.uuidString ?? vehicleModel ?? "unknown"):\(role.rawValue):\(address.map { "\($0.tx)->\($0.rx)" } ?? "none")"
        let dates = ([addressCandidate?.updatedAt] + [hardware, software, boot, calibration, serial]
            .filter(\.isAvailable)
            .map(\.updatedAt)).compactMap { $0 }
        return PTElectronicControlUnit(
            id: PTVehicleIdentityStableID.make(idSeed),
            role: role,
            reference: reference,
            diagnosticAddress: address,
            diagnosticAddressEvidenceIDs: addressCandidate?.evidenceIDs ?? [],
            hardwareVersion: hardware,
            softwareVersion: software,
            bootVersion: boot,
            calibrationID: calibration,
            serialNumber: serial,
            lastSeenAt: dates.max()
        )
    }

    static func makeAdapter(
        candidates: [EvidenceCandidate],
        profile: ProfileCandidateIndex,
        now: Date,
        vehicleID: UUID?,
        vehicleModel: String?
    ) -> PTDiagnosticAdapterIdentity? {
        let vendor = select(keys: [.adapterVendor], candidates: candidates, profile: profile, now: now)
        let model = select(keys: [.adapterModel], candidates: candidates, profile: profile, now: now)
        let firmware = select(keys: [.adapterFirmware], candidates: candidates, profile: profile, now: now)
        let transport = select(keys: [.adapterTransport], candidates: candidates, profile: profile, now: now)
        let ble = select(keys: [.adapterBLEFingerprint], candidates: candidates, profile: profile, now: now)
        let protocolFingerprint = select(keys: [.adapterProtocolFingerprint], candidates: candidates, profile: profile, now: now)
        let ota = selectBool(keys: [.adapterOTACapability], candidates: candidates, profile: profile, now: now)
        guard vendor.isAvailable || model.isAvailable || firmware.isAvailable || transport.isAvailable
                || ble.isAvailable || protocolFingerprint.isAvailable || ota.isAvailable else { return nil }

        let idSeed = "adapter:\(vehicleID?.uuidString ?? vehicleModel ?? "unknown")"
        return PTDiagnosticAdapterIdentity(
            id: PTVehicleIdentityStableID.make(idSeed),
            vendor: vendor,
            model: model,
            firmwareVersion: firmware,
            transport: transport,
            bleFingerprint: ble,
            protocolFingerprint: protocolFingerprint,
            supportsJieliOTA: ota
        )
    }

    static func makeTopology(
        identityID: UUID,
        vehicleID: UUID?,
        vehicleModel: String?,
        ecus: [PTElectronicControlUnit],
        adapter: PTDiagnosticAdapterIdentity?,
        generatedAt: Date
    ) -> PTVehicleElectronicTopology {
        let vehicleNodeID = "vehicle:\(identityID.uuidString)"
        var nodes = [
            PTVehicleTopologyNode(
                id: vehicleNodeID,
                kind: .vehicle,
                title: vehicleModel ?? "XP400",
                evidenceIDs: []
            )
        ]
        var edges: [PTVehicleTopologyEdge] = []

        for ecu in ecus {
            let nodeID = "ecu:\(ecu.id.uuidString)"
            nodes.append(
                PTVehicleTopologyNode(
                    id: nodeID,
                    kind: .ecu,
                    title: ecu.role.rawValue,
                    role: ecu.role,
                    diagnosticAddress: ecu.diagnosticAddress,
                    evidenceIDs: ecu.evidenceIDs
                )
            )
            edges.append(
                PTVehicleTopologyEdge(
                    id: "contains:\(vehicleNodeID):\(nodeID)",
                    fromNodeID: vehicleNodeID,
                    toNodeID: nodeID,
                    relation: .contains,
                    evidenceIDs: ecu.evidenceIDs
                )
            )
        }

        if let adapter {
            let adapterNodeID = "adapter:\(adapter.id.uuidString)"
            nodes.append(
                PTVehicleTopologyNode(
                    id: adapterNodeID,
                    kind: .diagnosticAdapter,
                    title: "YMOBD diagnostic adapter",
                    evidenceIDs: adapter.evidenceIDs
                )
            )
            edges.append(
                PTVehicleTopologyEdge(
                    id: "contains:\(vehicleNodeID):\(adapterNodeID)",
                    fromNodeID: vehicleNodeID,
                    toNodeID: adapterNodeID,
                    relation: .contains,
                    evidenceIDs: adapter.evidenceIDs
                )
            )

            if adapter.supportsJieliOTA.value == true {
                let otaNodeID = "ota:\(adapter.id.uuidString)"
                nodes.append(
                    PTVehicleTopologyNode(
                        id: otaNodeID,
                        kind: .otaCapability,
                        title: "Jieli adapter OTA capability",
                        evidenceIDs: adapter.supportsJieliOTA.evidenceIDs
                    )
                )
                edges.append(
                    PTVehicleTopologyEdge(
                        id: "supports:\(adapterNodeID):\(otaNodeID)",
                        fromNodeID: adapterNodeID,
                        toNodeID: otaNodeID,
                        relation: .supports,
                        evidenceIDs: adapter.supportsJieliOTA.evidenceIDs
                    )
                )
            }
        }

        return PTVehicleElectronicTopology(
            vehicleID: vehicleID,
            generatedAt: generatedAt,
            nodes: nodes,
            edges: edges
        )
    }

    static func select(
        keys: [PTVehicleIdentityFieldKey],
        candidates: [EvidenceCandidate],
        profile: ProfileCandidateIndex,
        now: Date
    ) -> PTEvidenceBackedValue<String> {
        if let candidate = best(keys: keys, candidates: candidates, profile: profile) {
            return PTEvidenceBackedValue(
                value: candidate.value,
                source: candidate.source,
                confidence: candidate.confidence,
                evidenceIDs: candidate.evidenceIDs,
                updatedAt: candidate.updatedAt,
                tier: candidate.tier
            )
        }
        return .unavailable(at: now)
    }

    static func selectBool(
        keys: [PTVehicleIdentityFieldKey],
        candidates: [EvidenceCandidate],
        profile: ProfileCandidateIndex,
        now: Date
    ) -> PTEvidenceBackedValue<Bool> {
        guard let candidate = best(keys: keys, candidates: candidates, profile: profile),
              let value = parseBool(candidate.value) else {
            return .unavailable(at: now)
        }
        return PTEvidenceBackedValue(
            value: value,
            source: candidate.source,
            confidence: candidate.confidence,
            evidenceIDs: candidate.evidenceIDs,
            updatedAt: candidate.updatedAt,
            tier: candidate.tier
        )
    }

    // EN: Accept only the explicit boolean words emitted by existing adapter profiles and evidence.
    // ES: Acepta solo las palabras booleanas explícitas emitidas por los perfiles y la evidencia existentes.
    // 中文：只接受现有适配器档案和证据明确输出的布尔词，不猜测其他文本。
    static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "supported", "available", "jieli ota supported (adapter only)": return true
        case "false", "no", "unsupported", "unavailable": return false
        default: return nil
        }
    }

    static func literalOrProfile(
        _ literal: String?,
        key: PTVehicleIdentityFieldKey,
        profile: ProfileCandidateIndex,
        now: Date
    ) -> PTEvidenceBackedValue<String> {
        if let literal = normalized(literal) {
            return PTEvidenceBackedValue(
                value: literal,
                source: .system,
                confidence: 0.8,
                updatedAt: now,
                tier: .storedProfile
            )
        }
        return select(keys: [key], candidates: [], profile: profile, now: now)
    }

    static func best(
        keys: [PTVehicleIdentityFieldKey],
        candidates: [EvidenceCandidate],
        profile: ProfileCandidateIndex
    ) -> EvidenceCandidate? {
        let evidenceMatches = candidates.filter { keys.contains($0.key) }
        if let winner = evidenceMatches.sorted(by: isBetter).first {
            return winner
        }
        return keys.compactMap { key in
            guard let field = profile.field(for: key), let value = normalized(field.value) else { return nil }
            return EvidenceCandidate(
                key: key,
                value: value,
                source: field.source,
                confidence: field.confidence,
                evidenceIDs: field.evidenceIDs,
                updatedAt: field.timestamp,
                tier: .storedProfile
            )
        }.sorted(by: isBetter).first
    }

    static func isBetter(_ lhs: EvidenceCandidate, _ rhs: EvidenceCandidate) -> Bool {
        if lhs.tier.rank != rhs.tier.rank { return lhs.tier.rank > rhs.tier.rank }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.evidenceIDs.map(\.uuidString).joined() < rhs.evidenceIDs.map(\.uuidString).joined()
    }

    static func fields(for identity: PTVehicleElectronicIdentity) -> [PTVehicleIdentityFieldKey: FieldSnapshot] {
        var fields: [PTVehicleIdentityFieldKey: FieldSnapshot] = [
            .vehicleModel: snapshot(identity.vehicleModel),
            .electronicReference: snapshot(identity.electronicReference)
        ]
        for ecu in identity.ecus {
            if supportsReference(for: ecu.role) {
                fields[referenceKey(for: ecu.role)] = snapshot(ecu.reference)
            }
            fields[hardwareKey(for: ecu.role)] = snapshot(ecu.hardwareVersion)
            fields[softwareKey(for: ecu.role)] = snapshot(ecu.softwareVersion)
            fields[bootKey(for: ecu.role)] = snapshot(ecu.bootVersion)
            if supportsCalibration(for: ecu.role) {
                fields[calibrationKey(for: ecu.role)] = snapshot(ecu.calibrationID)
            }
            fields[serialKey(for: ecu.role)] = snapshot(ecu.serialNumber)
            fields[addressKey(for: ecu.role)] = FieldSnapshot(
                value: ecu.diagnosticAddress.map { "\($0.tx)->\($0.rx)" },
                updatedAt: ecu.lastSeenAt ?? identity.generatedAt,
                evidenceIDs: ecu.diagnosticAddressEvidenceIDs
            )
        }
        if let adapter = identity.diagnosticAdapter {
            fields[.adapterVendor] = snapshot(adapter.vendor)
            fields[.adapterModel] = snapshot(adapter.model)
            fields[.adapterFirmware] = snapshot(adapter.firmwareVersion)
            fields[.adapterTransport] = snapshot(adapter.transport)
            fields[.adapterBLEFingerprint] = snapshot(adapter.bleFingerprint)
            fields[.adapterProtocolFingerprint] = snapshot(adapter.protocolFingerprint)
            fields[.adapterOTACapability] = FieldSnapshot(
                value: adapter.supportsJieliOTA.value.map { $0 ? "true" : "false" },
                updatedAt: adapter.supportsJieliOTA.updatedAt,
                evidenceIDs: adapter.supportsJieliOTA.evidenceIDs
            )
        }
        return fields
    }

    static func snapshot<Value>(_ value: PTEvidenceBackedValue<Value>) -> FieldSnapshot where Value: Codable & Sendable {
        FieldSnapshot(value: value.value.map(String.init(describing:)), updatedAt: value.updatedAt, evidenceIDs: value.evidenceIDs)
    }

    static func passportFields(
        for ecu: PTElectronicControlUnit,
        fallbackDate: Date
    ) -> [PTVehiclePassportField] {
        var fields = [
            passportField(hardwareKey(for: ecu.role), ecu.hardwareVersion),
            passportField(softwareKey(for: ecu.role), ecu.softwareVersion),
            passportField(bootKey(for: ecu.role), ecu.bootVersion),
            passportField(serialKey(for: ecu.role), ecu.serialNumber),
            PTVehiclePassportField(
                key: addressKey(for: ecu.role).rawValue,
                value: ecu.diagnosticAddress.map { "\($0.tx)->\($0.rx)" },
                source: ecu.diagnosticAddress == nil ? .unknown : (ecu.hardwareVersion.source),
                timestamp: ecu.lastSeenAt ?? fallbackDate,
                confidence: ecu.diagnosticAddress == nil ? 0 : max(ecu.hardwareVersion.confidence, ecu.softwareVersion.confidence),
                evidenceIDs: ecu.diagnosticAddressEvidenceIDs
            )
        ]
        if supportsReference(for: ecu.role) {
            fields.insert(passportField(referenceKey(for: ecu.role), ecu.reference), at: 0)
        }
        if supportsCalibration(for: ecu.role) {
            fields.insert(passportField(calibrationKey(for: ecu.role), ecu.calibrationID), at: 3)
        }
        return fields
    }

    static func passportField<Value>(_ key: PTVehicleIdentityFieldKey, _ value: PTEvidenceBackedValue<Value>) -> PTVehiclePassportField where Value: Codable & Sendable {
        PTVehiclePassportField(
            key: key.rawValue,
            value: value.value.map(String.init(describing:)),
            source: value.source,
            timestamp: value.updatedAt,
            confidence: value.confidence,
            evidenceIDs: value.evidenceIDs
        )
    }

    static func role(from pairs: [(String, String)], record: PTProtocolEvidenceRecord) -> PTECURole? {
        if record.domain == .ymobdVendorExtension || record.domain == .ymobdFirmwareOTA || record.kind == .adapterIdentity {
            return nil
        }
        let rawRole = pairs.first { key, _ in ["role", "ecu", "node"].contains(key) }?.1.lowercased()
        if let rawRole {
            switch rawRole {
            case "dashboard", "tft", "cluster", "instrument": return .dashboard
            case "connectivity", "connectivitybox", "telematics", "ble": return .connectivityBox
            case "engine", "ecu", "motor": return .engine
            case "abs", "brake": return .abs
            case "body", "bcm": return .body
            default: return .unknown
            }
        }
        return pairs.compactMap { fieldKey($0.0, role: nil, record: record) }.compactMap(role(for:)).first
    }

    static func role(for key: PTVehicleIdentityFieldKey) -> PTECURole? {
        switch key {
        case .dashboardReference, .dashboardHardware, .dashboardSoftware, .dashboardBoot, .dashboardSerial, .dashboardAddress:
            return .dashboard
        case .connectivityReference, .connectivityHardware, .connectivitySoftware, .connectivityBoot, .connectivitySerial, .connectivityBLEFingerprint, .connectivityProtocolFingerprint, .connectivityAddress:
            return .connectivityBox
        case .engineHardware, .engineSoftware, .engineBoot, .engineCalibration, .engineSerial, .engineAddress:
            return .engine
        case .absHardware, .absSoftware, .absBoot, .absCalibration, .absSerial, .absAddress:
            return .abs
        case .bodyHardware, .bodySoftware, .bodyBoot, .bodyCalibration, .bodySerial, .bodyAddress:
            return .body
        default: return nil
        }
    }

    static func fieldKey(
        _ rawKey: String,
        role: PTECURole?,
        record: PTProtocolEvidenceRecord
    ) -> PTVehicleIdentityFieldKey? {
        let normalizedKey = rawKey.lowercased().replacingOccurrences(of: "_", with: "")
        if let exact = PTVehicleIdentityFieldKey.allCases.first(where: {
            $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalizedKey
        }) {
            return exact
        }
        if record.domain == .ymobdVendorExtension || record.domain == .ymobdFirmwareOTA || record.kind == .adapterIdentity {
            switch normalizedKey {
            case "vendor": return .adapterVendor
            case "model": return .adapterModel
            case "firmware", "version": return .adapterFirmware
            case "transport": return .adapterTransport
            case "blefingerprint": return .adapterBLEFingerprint
            case "protocolfingerprint": return .adapterProtocolFingerprint
            case "otacapability", "jieliota": return .adapterOTACapability
            default: return nil
            }
        }
        guard let role else {
            switch normalizedKey {
            case "electronicreference", "vehicleelectronicreference": return .electronicReference
            case "vehiclemodel", "model": return .vehicleModel
            case "vin": return .vehicleVIN
            default: return nil
            }
        }
        switch normalizedKey {
        case "hw", "hardware", "hardwareversion": return hardwareKey(for: role)
        case "sw", "software", "softwareversion": return softwareKey(for: role)
        case "boot", "bootversion": return bootKey(for: role)
        case "serial", "serialnumber": return serialKey(for: role)
        case "calibration", "calibrationid": return supportsCalibration(for: role) ? calibrationKey(for: role) : nil
        case "reference", "electronicreference": return referenceKey(for: role)
        case "blefingerprint": return role == .connectivityBox ? .connectivityBLEFingerprint : nil
        case "protocolfingerprint": return role == .connectivityBox ? .connectivityProtocolFingerprint : nil
        case "address": return addressKey(for: role)
        default: return nil
        }
    }

    static func tokenPairs(in texts: [String?]) -> [(String, String)] {
        texts
            .compactMap { $0 }
            .flatMap { text in
                text.split { character in
                    character == "|" || character == ";" || character == "," || character == "\n" || character == "\r" || character == " "
                }.compactMap { token -> (String, String)? in
                    let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty, !value.isEmpty else { return nil }
                    return (key, value)
                }
            }
    }

    static func evidenceTier(for record: PTProtocolEvidenceRecord) -> PTVehicleIdentityEvidenceTier {
        if record.kind == .identity && record.confidence >= 0.95 { return .official }
        if record.source == .live { return .liveCaptured }
        if record.source == .imported || record.source == .replay || record.source == .migrated || record.source == .mock {
            return .repeatedCaptured
        }
        return .unavailable
    }

    static func isVehicleEvidence(_ record: PTProtocolEvidenceRecord, vehicleID: UUID?) -> Bool {
        guard record.domain != .ymobdVendorExtension, record.domain != .ymobdFirmwareOTA else { return false }
        return vehicleID == nil || record.vehicleID == nil || record.vehicleID == vehicleID
    }

    static func address(from pairs: [(String, String)], reference: String?) -> PTOBDiagnosticAddress? {
        if let value = pairs.first(where: { $0.0 == "address" })?.1,
           let parsed = parseAddress(value) { return parsed }
        if let tx = pairs.first(where: { $0.0 == "tx" })?.1,
           let rx = pairs.first(where: { $0.0 == "rx" })?.1,
           let parsed = PTOBDiagnosticAddress(tx: tx, rx: rx) { return parsed }
        guard let reference else { return nil }
        return parseAddress(reference)
    }

    static func parseAddress(_ value: String) -> PTOBDiagnosticAddress? {
        let parts = value.uppercased().replacingOccurrences(of: " ", with: "").components(separatedBy: "->")
        guard parts.count == 2 else { return nil }
        return PTOBDiagnosticAddress(tx: parts[0], rx: parts[1])
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : String(result.prefix(512))
    }

    static func identitySeed(vehicleID: UUID?, vehicleModel: String?) -> String {
        "vehicle:\(vehicleID?.uuidString ?? "none"):\(vehicleModel ?? "unknown")"
    }

    static func hardwareKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardHardware
        case .connectivityBox: return .connectivityHardware
        case .engine: return .engineHardware
        case .abs: return .absHardware
        case .body, .unknown: return .bodyHardware
        }
    }

    static func softwareKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardSoftware
        case .connectivityBox: return .connectivitySoftware
        case .engine: return .engineSoftware
        case .abs: return .absSoftware
        case .body, .unknown: return .bodySoftware
        }
    }

    static func bootKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardBoot
        case .connectivityBox: return .connectivityBoot
        case .engine: return .engineBoot
        case .abs: return .absBoot
        case .body, .unknown: return .bodyBoot
        }
    }

    static func calibrationKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardSoftware
        case .connectivityBox: return .connectivitySoftware
        case .engine: return .engineCalibration
        case .abs: return .absCalibration
        case .body, .unknown: return .bodyCalibration
        }
    }

    static func supportsCalibration(for role: PTECURole) -> Bool {
        role == .engine || role == .abs || role == .body
    }

    static func supportsReference(for role: PTECURole) -> Bool {
        role == .dashboard || role == .connectivityBox
    }

    static func serialKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardSerial
        case .connectivityBox: return .connectivitySerial
        case .engine: return .engineSerial
        case .abs: return .absSerial
        case .body, .unknown: return .bodySerial
        }
    }

    static func referenceKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardReference
        case .connectivityBox: return .connectivityReference
        case .engine, .abs, .body, .unknown: return .electronicReference
        }
    }

    static func addressKey(for role: PTECURole) -> PTVehicleIdentityFieldKey {
        switch role {
        case .dashboard: return .dashboardAddress
        case .connectivityBox: return .connectivityAddress
        case .engine: return .engineAddress
        case .abs: return .absAddress
        case .body, .unknown: return .bodyAddress
        }
    }
}
