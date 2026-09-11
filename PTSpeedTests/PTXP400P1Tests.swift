//
//  PTXP400P1Tests.swift
//  PTSpeedTests
//
//  EN: Regression tests for the P1 OBD coordination and ANCS boundaries.
//  ES: Pruebas de regresión para la coordinación OBD y los límites ANCS de P1.
//  中文：P1 OBD 协调与 ANCS 边界回归测试。
//

import XCTest
@testable import XP400Ride

final class PTXP400P1Tests: XCTestCase {
    func testBusLeaseSerializesDifferentUsers() async throws {
        let lease = PTOBDBusLease()
        let first = try await lease.acquire(kind: .sniffer)

        let waitingTask = Task {
            try await lease.acquire(kind: .diagnosticRead)
        }

        await waitUntilQueued(lease)
        let queuedCount = await lease.queuedCount
        let currentKind = await lease.currentKind
        XCTAssertEqual(queuedCount, 1)
        XCTAssertEqual(currentKind, .sniffer)

        await lease.release(first)
        let second = try await waitingTask.value
        XCTAssertEqual(second.kind, .diagnosticRead)
        let secondKind = await lease.currentKind
        XCTAssertEqual(secondKind, .diagnosticRead)
        await lease.release(second)
        let releasedKind = await lease.currentKind
        XCTAssertNil(releasedKind)
    }

    func testCancelledBusLeaseWaiterIsRemoved() async throws {
        let lease = PTOBDBusLease()
        let first = try await lease.acquire(kind: .sniffer)
        let waitingTask = Task {
            try await lease.acquire(kind: .diagnosticRead)
        }

        await waitUntilQueued(lease)
        waitingTask.cancel()

        do {
            _ = try await waitingTask.value
            XCTFail("A cancelled OBD lease waiter must not acquire the bus.")
        } catch is PTOBDBusLeaseError {
            // EN: Expected cancellation keeps the queue from retaining stale work.
            // ES: La cancelación esperada evita conservar trabajo obsoleto en la cola.
            // 中文：预期的取消结果确保队列不会保留过期任务。
        }

        let queuedCount = await lease.queuedCount
        XCTAssertEqual(queuedCount, 0)
        await lease.release(first)
        let releasedKind = await lease.currentKind
        XCTAssertNil(releasedKind)
    }

    func testDisconnectInvalidatesCurrentGeneration() async throws {
        let lease = PTOBDBusLease()
        let first = try await lease.acquire(kind: .sniffer)
        let waitingTask = Task {
            try await lease.acquire(kind: .diagnosticRead)
        }

        await waitUntilQueued(lease)
        await lease.invalidateForDisconnect()

        do {
            _ = try await waitingTask.value
            XCTFail("A disconnected OBD lease waiter must not cross into a new connection.")
        } catch PTOBDBusLeaseError.disconnected {
            // EN: Expected invalidation wakes queued work and prevents stale bus reuse.
            // ES: La invalidación esperada despierta el trabajo en cola y evita reutilizar el bus obsoleto.
            // 中文：预期的失效会唤醒排队任务，并阻止过期任务再次使用总线。
        }

        let isCurrent = await lease.isCurrent(first)
        XCTAssertFalse(isCurrent)
        await lease.release(first)
        let currentKind = await lease.currentKind
        XCTAssertNil(currentKind)
    }

    func testBusLeaseWaiterHasBoundedTimeout() async throws {
        let lease = PTOBDBusLease()
        let first = try await lease.acquire(kind: .sniffer)

        do {
            _ = try await lease.acquire(kind: .diagnosticRead, timeout: 0.001)
            XCTFail("A lease waiter past its deadline must not acquire the bus.")
        } catch PTOBDBusLeaseError.timedOut {
            // EN: Expected timeout keeps a blocked diagnostic from waiting forever.
            // ES: El tiempo de espera esperado evita que un diagnóstico bloqueado espere para siempre.
            // 中文：预期的超时避免阻塞的诊断任务永久等待。
        }

        let queuedCount = await lease.queuedCount
        XCTAssertEqual(queuedCount, 0)
        await lease.release(first)
    }

    func testCommandRiskClassificationUsesConservativeDefaults() {
        XCTAssertEqual(PTOBDCommandClassifier.classify("ATMA").risk, .passive)
        XCTAssertEqual(PTOBDCommandClassifier.classify("04").risk, .stateChanging)
        XCTAssertEqual(PTOBDCommandClassifier.classify("0801").risk, .stateChanging)
        XCTAssertEqual(PTOBDCommandClassifier.classify("05").risk, .readOnly)
        XCTAssertEqual(PTOBDCommandClassifier.classify("22 F1 90").risk, .readOnly)
        XCTAssertEqual(PTOBDCommandClassifier.classify("19 02").risk, .readOnly)
        XCTAssertEqual(PTOBDCommandClassifier.classify("10 03").risk, .stateChanging)
        XCTAssertEqual(PTOBDCommandClassifier.classify("2E F1 90 01").risk, .write)
        XCTAssertEqual(PTOBDCommandClassifier.classify("34 00").risk, .programming)
        XCTAssertEqual(PTOBDCommandClassifier.classify("11 01").risk, .stateChanging)
        XCTAssertEqual(PTOBDCommandClassifier.classify("99 GG").risk, .unknown)
        XCTAssertTrue(PTOBDCommandClassifier.isOrdinaryReadAllowed("22F190"))
        XCTAssertFalse(PTOBDCommandClassifier.isOrdinaryReadAllowed("22F1A0"))
        XCTAssertFalse(PTOBDCommandClassifier.isOrdinaryReadAllowed("23 24 00000000 0010"))
        XCTAssertTrue(PTOBDCommandClassifier.isCaptureAdapterCommand("ATCRA7E8"))
    }

    func testYMOBDVersionParserKeepsGenericELM327OnFallbackPath() {
        let parser = PTYMOBDVersionParser()
        let ymobdInfo = parser.parse("""
        AT+VERSION
        Company: PTools
        Version: V1.2.3
        Device Type: YMOBD
        Device Name: XP400
        Device MAC: aa:bb:cc
        Interface: BLE
        Cust ID: Peugeot
        Crypt: 12345678
        """)

        XCTAssertTrue(ymobdInfo.isYMOBD)
        XCTAssertEqual(ymobdInfo.company, "Company: PTools")
        XCTAssertEqual(ymobdInfo.version, "V1.2.3")
        XCTAssertEqual(ymobdInfo.deviceType, "YMOBD")
        XCTAssertEqual(ymobdInfo.deviceMac, "AA:BB:CC")
        XCTAssertEqual(ymobdInfo.customerID, "Peugeot")
        XCTAssertEqual(ymobdInfo.crypt, "12345678")

        let genericInfo = parser.parse("AT+VERSION\r\nELM327 v1.5\r\nVersion: 1.5\r\n")
        XCTAssertFalse(genericInfo.isYMOBD)
        XCTAssertNil(PTYMOBDAuthenticator().makeAuthCommand(versionInfo: genericInfo))
    }

    func testYMOBDAuthenticatorVerifiesChallengeResponse() throws {
        let info = PTYMOBDVersionInfo(deviceType: "YMOBD", isYMOBD: true)
        let authenticator = PTYMOBDAuthenticator()
        let result = try XCTUnwrap(authenticator.makeAuthCommand(versionInfo: info))
        let challenge = try XCTUnwrap(result.challenge)
        let expected = YmobdCrypt.hex8(
            value: YmobdCrypt.crypt32(input: Int32(bitPattern: challenge))
        )

        XCTAssertTrue(authenticator.verify(command: result.command, response: "\(expected)\r\n", challenge: challenge))
        XCTAssertTrue(authenticator.isOfficialYMOBD)
        XCTAssertFalse(authenticator.verify(command: result.command, response: "00000000\r\n", challenge: challenge))
    }

    func testYMOBDDeviceClassifierPreservesGenericAndExcludedRules() {
        let classifier = PTYMOBDDeviceClassifier()

        XCTAssertTrue(classifier.isLikelyOBD(deviceName: "obdii"))
        XCTAssertTrue(classifier.isLikelyOBD(deviceName: "Nearby Adapter", advertisedServiceUUIDs: ["FFF0"]))
        XCTAssertFalse(classifier.isLikelyOBD(deviceName: "P300"))
        XCTAssertFalse(classifier.isLikelyOBD(deviceName: "TPMS"))
        XCTAssertEqual(classifier.category(forName: "BT_00"), .batteryTester)
        XCTAssertEqual(classifier.category(forName: "C35"), .otaCapable)
    }

    func testYMOBDInitializerBoundsDebugAnd0100Retries() {
        let initializer = PTYMOBDInitializer()
        initializer.begin()
        XCTAssertEqual(initializer.state, .initializing)
        XCTAssertTrue(initializer.shouldSendDebugFlag(forYMOBD: true))
        XCTAssertFalse(initializer.shouldSendDebugFlag(forYMOBD: true))
        initializer.recordPID0100Mask(0x1E3E1001)
        XCTAssertEqual(initializer.pid0100Mask, 0x1E3E1001)

        for _ in 0..<PTYMOBDInitializer.maximum0100RetryCount {
            XCTAssertTrue(initializer.consume0100Retry())
        }
        XCTAssertFalse(initializer.consume0100Retry())
        XCTAssertEqual(initializer.state, .failed)
    }

    func testPollingProfilesExposeOfficialCadenceAndKeepAdaptiveDefault() {
        let supported = ["010C", "010D", "0105", "ATRV", "0104"]
        let official = PTOBDPollingProfile.officialYMOBD.makeQueue(from: supported)
        XCTAssertEqual(official.count, 25)
        XCTAssertEqual(Array(official.prefix(6)), ["010C", "010D", "010C", "0105", "010C", "ATRV"])
        XCTAssertEqual(official.last, "0104")

        let adaptive = PTOBDPollingProfile.adaptive.makeQueue(from: ["010C", "010D", "0105"])
        XCTAssertEqual(adaptive, ["010C", "010D", "0105"])
    }

    func testBLESessionStateAndCreditsAreResettableAndGenerationSafe() {
        var session = PTXP400BLESession()
        let firstToken = session.begin()
        XCTAssertTrue(session.accepts(firstToken))
        session.end()
        XCTAssertFalse(session.accepts(firstToken))

        var state = PTXP400BLEState(
            isAuthenticated: true,
            isTIOSubscribed: true,
            isCreditsSubscribed: true,
            sendCredits: 3,
            localCredits: 4
        )
        state.resetSession()
        XCTAssertEqual(state, PTXP400BLEState())

        var credits = PTXP400TIOCreditController()
        XCTAssertEqual(credits.acceptRemoteCredits(Data([3])), .accepted(amount: 3))
        XCTAssertTrue(credits.consumeRemoteCredit())
        XCTAssertEqual(credits.sendCredits, 2)
        XCTAssertEqual(credits.acceptRemoteCredits(Data([0])), .invalidAmount(actual: 0))
        XCTAssertEqual(credits.refillLocalCredits(), PTXP400BLEProtocol.maxCredits)
    }

    func testTelemetryEnvelopeAndNavigationSchedulerStayPure() {
        let frame = Data([0x16, PTXP400BLEProtocol.data1FrameID, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x00])
        let decoded = PTXP400TelemetryDecoder.decode(frame)
        XCTAssertEqual(decoded?.id, PTXP400BLEProtocol.data1FrameID)
        XCTAssertEqual(decoded?.payload, Data([1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertEqual(PTXP400TelemetryDecoder.kind(for: PTXP400BLEProtocol.data1FrameID), .data1)
        XCTAssertNil(PTXP400TelemetryDecoder.decode(Data([0x00, 0x02, 0x00])))

        let info = PTNavigationInfo(
            nextManeuver: PTManeuverMap.straight,
            metersToNextManeuver: 100,
            nameNextRoad: "A",
            nameCurrentRoad: "B",
            currentSpeedLimit: 50,
            distanceToDestination: 1_000,
            estimatedTimeToDestinationSec: 120
        )
        let fingerprint = PTXP400NavigationFingerprint(info: info)
        var scheduler = PTXP400NavigationScheduler(minimumSendInterval: 0.5)
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(scheduler.isDuplicate(fingerprint))
        scheduler.recordSent(fingerprint, at: now)
        XCTAssertTrue(scheduler.isDuplicate(fingerprint))
        XCTAssertEqual(scheduler.remainingDelay(at: now.addingTimeInterval(0.25)), 0.25, accuracy: 0.001)
        scheduler.reset()
        XCTAssertFalse(scheduler.isDuplicate(fingerprint))
    }

    @MainActor
    func testANCSCoordinatorDefaultsToSystemChannel() {
        XCTAssertEqual(PTXP400ANCSCoordinator.shared.channel, .system)
    }

    // EN: Give the child task a bounded opportunity to enter the actor queue without an unbounded sleep.
    // ES: Permite que la tarea hija entre en la cola del actor con una espera acotada.
    // 中文：给子任务一个有界机会进入 actor 队列，避免无界等待。
    private func waitUntilQueued(_ lease: PTOBDBusLease) async {
        for _ in 0..<50 {
            if await lease.queuedCount > 0 {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
