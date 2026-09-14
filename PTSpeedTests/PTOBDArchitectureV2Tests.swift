//
//  PTOBDArchitectureV2Tests.swift
//  PTSpeedTests
//
//  EN: Regression tests for the Build 57 OBD Architecture 2.0 boundaries.
//  ES: Pruebas de regresión para los límites de OBD Architecture 2.0 de Build 57.
//  中文：覆盖 Build 57 OBD Architecture 2.0 边界的回归测试。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTOBDArchitectureV2Tests: XCTestCase {
    func testBundledFixturesUseRealPromptAndPayloadBoundaries() throws {
        let pidFixture = try loadFixture("OBD/Fixtures/PID/010C")
        var parser = PTELM327Parser()
        let pidResponses = parser.append(Data(pidFixture.utf8))

        XCTAssertEqual(pidResponses.count, 1)
        XCTAssertEqual(pidResponses.first?.payloadLines, ["010C", "7E8 04 41 0C 1F A0"])
        XCTAssertTrue(pidResponses.first?.isPromptTerminated == true)

        let echoFixture = try loadFixture("OBD/Fixtures/ELM/echo_on")
        let echoResponse = PTELM327Parser.parse(
            raw: echoFixture,
            command: "ATZ",
            promptTerminated: true
        )
        XCTAssertEqual(echoResponse.payloadLines, ["ELM327 v1.5"])

        let udsFixture = try loadFixture("OBD/Fixtures/UDS/positive")
        parser.reset()
        let udsResponses = parser.append(Data(udsFixture.utf8))
        XCTAssertEqual(udsResponses.first?.status, .positive)

        let udsNegativeFixture = try loadFixture("OBD/Fixtures/UDS/negative")
        parser.reset()
        let udsNegativeResponses = parser.append(Data(udsNegativeFixture.utf8))
        XCTAssertEqual(udsNegativeResponses.first?.payloadLines.last, "7F 22 31")

        let versionFixture = try loadFixture("OBD/Fixtures/YMOBD/version")
        let versionInfo = PTYMOBDVersionParser().parse(versionFixture)
        XCTAssertTrue(versionInfo.isYMOBD)
        XCTAssertEqual(versionInfo.deviceType, "YMOBD")
        XCTAssertEqual(versionInfo.crypt, "12345678")
    }

    func testPromptParserHandlesFragmentsAndKnownStatuses() {
        var parser = PTELM327Parser()
        XCTAssertTrue(parser.append(Data("010C\r\n7E8 04 41 0C".utf8)).isEmpty)

        let responses = parser.append(Data(" 1F A0\r\n>".utf8))
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses[0].status, .positive)
        XCTAssertEqual(responses[0].payloadLines, ["010C", "7E8 04 41 0C 1F A0"])

        let noData = PTELM327Parser.parse(raw: "NO DATA\r\n>", promptTerminated: true)
        XCTAssertEqual(noData.status, .noData)
        XCTAssertTrue(noData.isPromptTerminated)
    }

    func testCommandClassifierV2KeepsOTAOutsideELMCommands() {
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("ATE0").kind, .elmConfiguration)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("010C").kind, .telemetryRead)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("22 F1 90").kind, .diagnosticRead)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("AT+VERSION").kind, .vendorManagement)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("ATMA").kind, .canMonitor)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("2EF19001").kind, .diagnosticMutation)
        XCTAssertEqual(PTOBDCommandClassifierV2.classify("AT+JIELIOTA").kind, .rawUnknown)
        XCTAssertEqual(PTAdapterMaintenanceOperation.firmwareUpdate.rawValue, "firmwareUpdate")
    }

    func testMockTransportAndSessionUseOneSerializedELMPath() async throws {
        let transport = await MainActor.run {
            PTOBDMockTransport { data in
                let command = String(data: data, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() ?? ""
                switch command {
                case "010C":
                    return Data("7E8 04 41 0C 1F A0\r\n>".utf8)
                case "AT+VERSION":
                    return Data("Company: PTools\r\nVersion: V2.5.0\r\nDevice Type: YMOBD\r\nDevice Name: XP400\r\n>".utf8)
                default:
                    return Data("OK\r\n>".utf8)
                }
            }
        }
        let session = PTELM327Session(transport: transport, transportKind: .mock)
        try await session.connect()
        await session.markReady()

        let response = try await session.execute("010C")
        XCTAssertEqual(response.status, .positive)
        XCTAssertEqual(response.payloadLines.last, "7E8 04 41 0C 1F A0")
        let capabilities = await session.capabilities
        XCTAssertEqual(capabilities.transportKind, .mock)

        await session.disconnect()
        let state = await session.state
        XCTAssertEqual(state, .disconnected)
    }

    func testCommandQueueNeverRunsTwoOperationsAtOnce() async throws {
        actor Probe {
            var active = 0
            var maximum = 0

            func enter() {
                active += 1
                maximum = max(maximum, active)
            }

            func leave() {
                active -= 1
            }
        }

        let probe = Probe()
        let queue = PTELM327CommandQueue()
        let tasks = (0..<4).map { index in
            Task {
                let request = PTELM327Request(command: "01\(String(format: "%02X", index))")
                return try await queue.enqueue(request) {
                    await probe.enter()
                    try await Task.sleep(for: .milliseconds(5))
                    await probe.leave()
                    return PTELM327Parser.parse(raw: "41\(String(format: "%02X", index))", promptTerminated: true)
                }
            }
        }

        for task in tasks {
            _ = try await task.value
        }
        let maximum = await probe.maximum
        XCTAssertEqual(maximum, 1)
        let isIdle = await queue.isIdle
        XCTAssertTrue(isIdle)
    }

    func testCommandQueueTimeoutCancelsUnderlyingOperation() async throws {
        let queue = PTELM327CommandQueue()
        let firstRequest = PTELM327Request(
            command: "010C",
            timeout: .milliseconds(10)
        )

        do {
            _ = try await queue.enqueue(firstRequest) {
                try await Task.sleep(for: .seconds(60))
                return PTELM327Parser.parse(raw: "41 0C", promptTerminated: true)
            }
            XCTFail("The first request should time out")
        } catch let error as PTELM327CommandQueueError {
            XCTAssertEqual(error, .timedOut(firstRequest.id))
        }

        let secondResponse = try await queue.enqueue(
            PTELM327Request(command: "010D")
        ) {
            PTELM327Parser.parse(raw: "41 0D", promptTerminated: true)
        }
        XCTAssertEqual(secondResponse.raw, "41 0D")
    }

    func testMonitorCanYieldImmediatelyAfterStart() async {
        let monitor = PTELM327Monitor()
        let stream = await monitor.start()
        let expected = PTELM327Parser.parse(raw: "41 0C", promptTerminated: true)
        await monitor.yield(expected)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received, expected)
        await monitor.stop()
    }

    func testYMOBDExtensionUsesSharedSessionAndRejectsGenericFallback() async throws {
        let transport = await MainActor.run {
            PTOBDMockTransport { data in
                let command = String(data: data, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() ?? ""
                if command == "AT+VERSION" {
                    return Data("Company: PTools\r\nVersion: V2.5.0\r\nDevice Type: YMOBD\r\nDevice Name: XP400\r\nCrypt: 12345678\r\n>".utf8)
                }
                return Data("OK\r\n>".utf8)
            }
        }
        let session = PTELM327Session(transport: transport, transportKind: .mock)
        try await session.connect()
        await session.markReady()

        let extensionProvider = await MainActor.run { PTYMOBDVendorExtension() }
        XCTAssertTrue(try await extensionProvider.probe(session: session))
        let capabilities = await session.capabilities
        XCTAssertEqual(capabilities.vendor?.deviceType, "YMOBD")
        XCTAssertTrue(capabilities.vendor?.supportsFirmwareCheck == true)

        await session.disconnect()
    }

    func testAdapterModeRequiresDeveloperGateAndExplicitConfirmation() async throws {
        let coordinator = PTYMOBDAdapterModeCoordinator()
        await coordinator.markELMConnected()

        do {
            try await coordinator.performOTA(
                explicitlyConfirmed: false,
                hooks: PTYMOBDAdapterModeHooks(
                    startJieliOTA: {},
                    restoreELM: {},
                    verifyELM: { true }
                )
            )
            XCTFail("OTA should require explicit confirmation")
        } catch let error as PTYMOBDAdapterModeError {
            XCTAssertEqual(error, .confirmationRequired)
        }
    }

    func testSessionTraceIsBoundedAndKeepsDistinctIdentifiers() async {
        let trace = PTOBDSessionTrace(maximumEventCount: 2)
        let identifiers = await trace.begin()
        await trace.record(name: "one")
        await trace.record(name: "two")
        await trace.record(name: "three")
        let snapshot = await trace.snapshot()

        XCTAssertEqual(snapshot.identifiers, identifiers)
        XCTAssertEqual(snapshot.events.map(\.name), ["two", "three"])
        XCTAssertNotEqual(identifiers.elmSessionID, identifiers.otaSessionID)
        XCTAssertNotEqual(identifiers.obdTransportSessionID, identifiers.adapterSessionID)
    }

    private func loadFixture(_ relativePath: String) throws -> String {
        let path = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard let fileName = path.last else {
            throw FixtureError.invalidPath(relativePath)
        }

        let directory = path.dropLast().joined(separator: "/")
        let bundle = Bundle(for: PTOBDArchitectureV2Tests.self)
        let url = bundle.url(
            forResource: String(fileName),
            withExtension: "txt",
            subdirectory: directory.isEmpty ? nil : directory
        ) ?? bundle.url(forResource: String(fileName), withExtension: "txt")

        guard let url else {
            throw FixtureError.missing(relativePath)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private enum FixtureError: Error {
    case invalidPath(String)
    case missing(String)
}
