//
//  PTVehicleIdentityBuild64Tests.swift
//  CrazyDashboard
//
//  EN: Verifies Build 64 identity provenance, read-only enumeration, topology persistence, and diffs.
//  ES: Verifica la procedencia, enumeración de solo lectura, persistencia de topología y diferencias de Build 64.
//  中文：验证 Build 64 身份来源、只读枚举、拓扑持久化和差异。
//

import XCTest
@testable import XP400Ride

final class PTVehicleIdentityBuild64Tests: XCTestCase {
    private let vehicleID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000064")!
    private let officialEvidenceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!
    private let liveEvidenceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000002")!
    private let adapterEvidenceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000003")!
    private let connectivityEvidenceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000004")!

    func testEvidenceBackedValueWithoutEvidenceRemainsStoredProfile() {
        let value = PTEvidenceBackedValue(
            value: "manual-profile",
            source: .system,
            confidence: 1,
            tier: .official
        )

        XCTAssertEqual(value.tier, .storedProfile)
        XCTAssertFalse(value.isTraceable)
    }

    func testLegacyPassportFieldDecodesWithoutEvidenceIDs() throws {
        let data = Data("""
        {"key":"dashboard.hardware","value":"legacy-hardware","source":"system","timestamp":1800000000,"confidence":0.7}
        """.utf8)

        let field = try JSONDecoder().decode(PTVehiclePassportField.self, from: data)
        XCTAssertEqual(field.value, "legacy-hardware")
        XCTAssertTrue(field.evidenceIDs.isEmpty)
    }

    func testCatalogRequiresEvidenceAndExplicitCandidateSelection() {
        var catalog = PTXP400ReadOnlyDIDCatalog()
        XCTAssertFalse(catalog.canRead(did: "F190"))
        XCTAssertFalse(catalog.canRead(did: "F199"))

        catalog.insertCandidate(
            did: "F187",
            title: "Vehicle software identification",
            evidenceIDs: [liveEvidenceID]
        )
        XCTAssertFalse(catalog.canRead(did: "F187"))
        XCTAssertTrue(catalog.canRead(did: "F187", explicitlySelected: true))
        XCTAssertEqual(catalog.explicitlySelectedDefinitions(for: ["F187"]).count, 1)

        let target = PTReadOnlyECUProbeTarget(
            role: .dashboard,
            diagnosticAddress: PTOBDDiagnosticAddress(tx: "700", rx: "708")!,
            dids: ["F187"]
        )
        let plan = PTReadOnlyECUEnumerationPlan(targets: [target])
        XCTAssertEqual(plan.requests(using: catalog).map(\.requestHex), ["3E"])
        XCTAssertEqual(
            plan.requests(using: catalog, explicitlySelectedDIDs: ["F187"]).map(\.requestHex),
            ["3E", "22F187"]
        )
    }

    func testReadOnlyPolicyRejectsMutationServices() {
        XCTAssertEqual(PTReadOnlyECUEnumerationPolicy.classify(requestHex: "22 F1 90"), .readDID)
        XCTAssertEqual(PTReadOnlyECUEnumerationPolicy.classify(requestHex: "3E"), .testerPresent)
        XCTAssertEqual(PTReadOnlyECUEnumerationPolicy.classify(requestHex: "27 01"), .forbiddenMutation)
        XCTAssertEqual(PTReadOnlyECUEnumerationPolicy.classify(requestHex: "2E F1 90 01"), .forbiddenMutation)
        XCTAssertFalse(PTReadOnlyECUEnumerationPolicy.isReadOnly(requestHex: "31 01"))
        XCTAssertFalse(
            PTReadOnlyECUEnumerationPolicy.isReadOnly(
                requestHex: "22F199",
                allowedDIDs: ["F190"]
            )
        )
        XCTAssertTrue(
            PTReadOnlyECUEnumerationPolicy.isReadOnly(
                requestHex: "22F190",
                allowedDIDs: ["F190"]
            )
        )
        XCTAssertTrue(PTReadOnlyECUEnumerationPolicy.isPositiveResponse(requestHex: "22F190", responseHex: "62F1900102"))
        XCTAssertTrue(PTReadOnlyECUEnumerationPolicy.isNegativeResponse(responseHex: "7F2278"))
    }

    func testResolverUsesOfficialEvidenceBeforeLiveAndStoredProfile() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let address = PTOBDDiagnosticAddress(tx: "700", rx: "708")!
        let storedField = PTVehiclePassportField(
            key: PTVehicleIdentityFieldKey.dashboardHardware.rawValue,
            value: "profile-hardware",
            source: .system,
            timestamp: now.addingTimeInterval(-300),
            confidence: 0.99
        )
        let liveRecord = PTProtocolEvidenceRecord(
            id: liveEvidenceID,
            domain: .uds,
            kind: .identity,
            direction: .rx,
            source: .live,
            timestamp: now.addingTimeInterval(-120),
            confidence: 0.75,
            value: "role=dashboard hw=live-hardware sw=1.0.3",
            request: "22F187",
            response: "62F187",
            reference: "700->708"
        )
        let officialRecord = PTProtocolEvidenceRecord(
            id: officialEvidenceID,
            domain: .uds,
            kind: .identity,
            direction: .rx,
            source: .imported,
            timestamp: now.addingTimeInterval(-60),
            confidence: 1,
            value: "role=dashboard hw=official-hardware sw=1.0.4 boot=1.0 serial=CLUSTER-01",
            request: "22F187",
            response: "62F187",
            reference: "700->708",
            note: "official evidence"
        )
        let adapterRecord = PTProtocolEvidenceRecord(
            id: adapterEvidenceID,
            domain: .ymobdVendorExtension,
            kind: .adapterIdentity,
            direction: .state,
            source: .live,
            timestamp: now,
            confidence: 0.9,
            value: "vendor=YMOBD model=JLink version=1.2.3",
            reference: "AT+VERSION"
        )
        let connectivityRecord = PTProtocolEvidenceRecord(
            id: connectivityEvidenceID,
            domain: .xp400BLE,
            kind: .identity,
            direction: .rx,
            source: .live,
            timestamp: now,
            confidence: 0.9,
            value: "role=connectivity reference=CB-REF-01 hw=2.0 sw=3.1 boot=1.0 bleFingerprint=CB-BLE",
            reference: "central=CB-REF-01"
        )
        let otaRecord = PTProtocolEvidenceRecord(
            domain: .ymobdFirmwareOTA,
            kind: .firmwareOTA,
            source: .live,
            timestamp: now,
            confidence: 0.9,
            value: "state=available"
        )

        let identity = PTVehicleIdentityResolver.resolve(
            PTVehicleElectronicIdentityResolutionInput(
                vehicleID: vehicleID,
                vehicleModel: "XP400 GT",
                storedProfile: [storedField],
                evidence: [liveRecord, officialRecord, adapterRecord, connectivityRecord, otaRecord],
                now: now
            )
        )

        XCTAssertEqual(identity.dashboard?.hardwareVersion.value, "official-hardware")
        XCTAssertEqual(identity.dashboard?.hardwareVersion.tier, .official)
        XCTAssertNil(identity.dashboard?.reference.value)
        XCTAssertEqual(identity.dashboard?.diagnosticAddress, address)
        XCTAssertEqual(identity.dashboard?.serialNumber.value, "CLUSTER-01")
        XCTAssertEqual(identity.connectivityBox?.reference.value, "CB-REF-01")
        XCTAssertTrue(identity.connectivityBox?.reference.evidenceIDs.contains(connectivityEvidenceID) == true)
        XCTAssertNil(identity.engine)
        XCTAssertEqual(identity.diagnosticAdapter?.vendor.value, "YMOBD")
        XCTAssertEqual(identity.diagnosticAdapter?.supportsJieliOTA.value, true)
        XCTAssertTrue(identity.topology.nodes.contains { $0.kind == .diagnosticAdapter })
        XCTAssertTrue(identity.topology.nodes.contains { $0.kind == .otaCapability })
        XCTAssertTrue(identity.dashboard?.evidenceIDs.contains(officialEvidenceID) == true)

        let passport = PTVehicleIdentityResolver.makePassport(from: identity, at: now)
        XCTAssertEqual(
            passport.field(for: PTVehicleIdentityFieldKey.dashboardHardware.rawValue)?.value,
            "official-hardware"
        )
        XCTAssertTrue(
            passport.field(for: PTVehicleIdentityFieldKey.dashboardHardware.rawValue)?.evidenceIDs.contains(officialEvidenceID) == true
        )
    }

    func testEnumerationEvaluatesOnlyReadOnlyEvidence() {
        let address = PTOBDiagnosticAddress(tx: "700", rx: "708")!
        let target = PTReadOnlyECUProbeTarget(role: .dashboard, diagnosticAddress: address, dids: ["F190"])
        let positive = PTProtocolEvidenceRecord(
            id: officialEvidenceID,
            domain: .uds,
            kind: .response,
            direction: .rx,
            source: .live,
            confidence: 1,
            value: "DID=F190",
            request: "22F190",
            response: "62F1900102",
            reference: "700->708"
        )
        let mutation = PTProtocolEvidenceRecord(
            id: liveEvidenceID,
            domain: .uds,
            kind: .response,
            direction: .rx,
            source: .live,
            confidence: 1,
            value: "write attempt",
            request: "2EF19001",
            response: "6EF190",
            reference: "700->708"
        )
        let report = PTReadOnlyECUEnumerationEvaluator.evaluate(
            records: [positive, mutation],
            targets: [target]
        )

        XCTAssertEqual(report.observations.count, 1)
        XCTAssertEqual(report.observations.first?.outcome, .positive)
        XCTAssertEqual(report.observations.first?.evidenceID, officialEvidenceID)
        XCTAssertTrue(report.ignoredEvidenceIDs.contains(liveEvidenceID))
    }

    func testIdentityDiffFindsSoftwareChangeAndKeepsStableIdentityID() {
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(120)
        let first = makeIdentity(software: "1.0.3", date: firstDate, evidenceID: liveEvidenceID)
        let second = makeIdentity(software: "1.0.4", date: secondDate, evidenceID: officialEvidenceID)
        let diff = PTVehicleIdentityResolver.diff(old: first, new: second, at: secondDate)

        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(diff.hasChanges)
        let change = diff.changes.first { $0.key == .dashboardSoftware }
        XCTAssertEqual(change?.kind, .changed)
        XCTAssertEqual(change?.oldValue, "1.0.3")
        XCTAssertEqual(change?.newValue, "1.0.4")
        XCTAssertEqual(change?.firstSeenAt, firstDate)
        XCTAssertEqual(change?.lastSeenAt, secondDate)
        XCTAssertTrue(change?.evidenceIDs.contains(officialEvidenceID) == true)
    }

    func testIdentityStorePersistsTopologyAndDiff() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PTVehicleIdentity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = makeIdentity(software: "1.0.3", date: firstDate, evidenceID: liveEvidenceID)
        let second = makeIdentity(software: "1.0.4", date: secondDate, evidenceID: officialEvidenceID)
        let store = try PTVehicleIdentityStore(url: url)
        _ = try await store.upsert(first)
        let savedDiff = try await store.upsert(second)

        XCTAssertEqual(savedDiff.changes.first { $0.key == .dashboardSoftware }?.newValue, "1.0.4")
        let storedTopology = await store.latestIdentity(for: vehicleID)?.topology
        XCTAssertEqual(storedTopology, second.topology)

        let reopened = try PTVehicleIdentityStore(url: url)
        let reopenedIdentityID = await reopened.latestIdentity(for: vehicleID)?.id
        let reopenedDiffCount = await reopened.diffs(for: vehicleID).count
        XCTAssertEqual(reopenedIdentityID, second.id)
        XCTAssertEqual(reopenedDiffCount, 2)
    }

    private func makeIdentity(software: String, date: Date, evidenceID: UUID) -> PTVehicleElectronicIdentity {
        let record = PTProtocolEvidenceRecord(
            id: evidenceID,
            domain: .uds,
            kind: .identity,
            direction: .rx,
            source: .live,
            timestamp: date,
            confidence: 1,
            value: "role=dashboard sw=\(software)",
            request: "22F187",
            response: "62F187",
            reference: "700->708"
        )
        return PTVehicleIdentityResolver.resolve(
            PTVehicleElectronicIdentityResolutionInput(
                vehicleID: vehicleID,
                vehicleModel: "XP400 GT",
                evidence: [record],
                now: date
            )
        )
    }
}
