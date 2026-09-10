//
//  PTXP400BLEP0Tests.swift
//  CrazyDashboard
//
//  EN: P0 regression tests for authentication, TIO credits, frames, lifecycle, and timeouts.
//  ES: Pruebas de regresión P0 para autenticación, créditos TIO, tramas, ciclo de vida y tiempos de espera.
//  中文：覆盖认证、TIO Credits、协议帧、生命周期和超时的 P0 回归测试。
//

import XCTest
@testable import XP400Ride

final class PTXP400BLEP0Tests: XCTestCase {
    // EN: Prevent the stable frame builder from drifting away from the shared wire contract.
    // ES: Evita que el constructor de tramas estable se desvíe del contrato de cableado compartido.
    // 中文：防止稳定帧构造器与共享线协议契约发生漂移。
    func testFrameBuilderUsesTheSharedProtocolContract() {
        XCTAssertEqual(PTFrameBuilder.PREAMBLE, PTXP400BLEProtocol.preamble)
        XCTAssertEqual(PTFrameBuilder.END_OF_FRAME, PTXP400BLEProtocol.terminator)
        XCTAssertEqual(PTFrameBuilder.ID_NAVIGATION, PTXP400BLEProtocol.navigationFrameID)
        XCTAssertEqual(PTFrameBuilder.ID_CONFIGURATION, PTXP400BLEProtocol.configurationFrameID)
    }

    // EN: The authentication fixture locks the deterministic response prefix without storing the random suffix.
    // ES: El fixture de autenticación fija el prefijo determinista sin guardar el sufijo aleatorio.
    // 中文：认证 Fixture 锁定确定性的响应前缀，不保存随机后缀。
    @MainActor
    func testAuthenticationFixturePreservesKnownBoundariesAndPrefix() {
        XCTAssertTrue(
            PTXP400BLEProtocol.isValidAuthenticationKeyConfiguration(
                PTXP400BLEP0Fixtures.dashboardKeyConfiguration
            )
        )
        XCTAssertTrue(
            PTXP400BLEProtocol.isValidAuthenticationChallenge(
                PTXP400BLEP0Fixtures.firstChallenge
            )
        )
        XCTAssertTrue(
            PTXP400BLEProtocol.isValidAuthenticationChallenge(
                PTXP400BLEP0Fixtures.secondChallenge
            )
        )
        XCTAssertEqual(
            PTXP400BLEProtocol.connectionSerial(in: PTXP400BLEP0Fixtures.connectionFrame),
            "A1B2C3D4E5F6"
        )

        let authentication = PTScooterAuth()
        let response = authentication.createAuthenticationMessage(
            r: (0..<10).map { UInt16($0) }
        )

        XCTAssertEqual(response.count, PTXP400BLEProtocol.authenticationChallengeLength)
        XCTAssertEqual(
            Data(response.prefix(PTXP400BLEP0Fixtures.firstResponsePrefix.count)),
            PTXP400BLEP0Fixtures.firstResponsePrefix
        )
    }

    // EN: Credits and navigation fixtures protect the exact envelope and big-endian distance fields.
    // ES: Los fixtures de créditos y navegación protegen la envoltura exacta y las distancias big-endian.
    // 中文：Credits 和导航 Fixture 保护精确包络及大端距离字段。
    func testCreditsAndNavigationFixturesPreserveWireShape() {
        XCTAssertEqual(
            PTXP400BLEProtocol.validatedRemoteCreditValue(
                in: PTXP400BLEP0Fixtures.fullCreditGrant
            ),
            PTXP400BLEProtocol.maxCredits
        )
        XCTAssertTrue(
            PTXP400BLEProtocol.canAcceptRemoteCredits(
                current: 0,
                adding: PTXP400BLEProtocol.maxCredits
            )
        )

        let frame = PTFrameBuilder.buildNavigationFrame(info: PTXP400BLEP0Fixtures.navigationInfo)
        XCTAssertTrue(PTXP400BLEProtocol.isValidOutboundFrame(frame))
        XCTAssertEqual(frame[0], PTXP400BLEProtocol.preamble)
        XCTAssertEqual(frame[1], PTXP400BLEProtocol.navigationFrameID)

        let declaredLength = (Int(frame[2]) << 8) | Int(frame[3])
        XCTAssertEqual(frame.count, declaredLength + 5)

        let payload = Data(frame.dropFirst(4).dropLast())
        XCTAssertEqual(payload[0], 1)
        XCTAssertEqual(payload[1], PTXP400BLEP0Fixtures.navigationInfo.nextManeuver)
        XCTAssertEqual(payload[2], 4)
        XCTAssertEqual(
            Data(payload[3..<7]),
            Data([0x00, 0x00, 0x00, 0x7D])
        )

        let nextRoadLength = Int(payload[7])
        let nextRoadStart = 8
        let nextRoad = Data(payload[nextRoadStart..<(nextRoadStart + nextRoadLength)])
        XCTAssertEqual(String(decoding: nextRoad, as: UTF8.self), "Rue de Lyon")
    }

    // EN: Data1, Data2, Data3, and ABS fixtures remain strict eleven-byte vehicle frames.
    // ES: Los fixtures Data1, Data2, Data3 y ABS siguen siendo tramas estrictas de once bytes.
    // 中文：Data1、Data2、Data3 和 ABS Fixture 必须保持严格的 11 字节车辆帧。
    func testVehicleStatusFixturesSurviveMergedAndSplitIngress() {
        let frames = [
            PTXP400BLEP0Fixtures.data1Frame,
            PTXP400BLEP0Fixtures.data2Frame,
            PTXP400BLEP0Fixtures.data3Frame,
            PTXP400BLEP0Fixtures.absFrame
        ]
        var merged = Data()
        for frame in frames {
            XCTAssertEqual(frame.count, PTXP400BLEProtocol.vehicleStatusFrameLength)
            XCTAssertTrue(PTXP400BLEProtocol.isVehicleStatusFrame(frame))
            merged.append(frame)
        }

        var reassembler = PTXP400BLEInboundReassembler()
        reassembler.append(Data(merged.prefix(7)))
        XCTAssertEqual(reassembler.nextFrame(for: .vehicleStatus), .waiting)
        reassembler.append(Data(merged.dropFirst(7)))

        for frame in frames {
            XCTAssertEqual(reassembler.nextFrame(for: .vehicleStatus), .frame(frame))
        }
        XCTAssertEqual(reassembler.nextFrame(for: .vehicleStatus), .waiting)
    }

    // EN: Invalid lifecycle transitions do not silently unlock the ready state.
    // ES: Las transiciones inválidas no desbloquean silenciosamente el estado listo.
    // 中文：非法生命周期转换不能静默进入 ready 状态。
    func testLifecycleMachineRequiresTheAuthenticatedSequence() {
        var machine = PTXP400BLELifecycleMachine()
        XCTAssertEqual(
            machine.handle(.authenticationSucceeded),
            .idle
        )

        let expectedStates: [PTXP400BLELifecycleState] = [
            .configuringService,
            .configuringService,
            .configuringService,
            .advertising,
            .centralConnected,
            .waitingForSubscriptions,
            .authenticating,
            .authenticating,
            .ready
        ]
        let events: [PTXP400BLELifecycleEvent] = [
            .startRequested,
            .serviceConfigurationStarted,
            .serviceConfigured,
            .advertisingStarted,
            .centralConnected,
            .subscriptionsWaiting,
            .subscriptionsReady,
            .authenticationStarted,
            .authenticationSucceeded
        ]

        for (event, expectedState) in zip(events, expectedStates) {
            XCTAssertEqual(machine.handle(event), expectedState)
        }
        XCTAssertTrue(machine.state.isReady)

        XCTAssertEqual(
            machine.handle(.timeout(.connectionFrame)),
            .failed(.timeout(.connectionFrame))
        )
        XCTAssertEqual(machine.handle(.disconnected), .idle)
    }

    // EN: A canceled watchdog cannot fire, while the active phase fires exactly once and then disarms.
    // ES: Un watchdog cancelado no puede dispararse; la fase activa se dispara una vez y luego se desarma.
    // 中文：已取消的 watchdog 不能触发；活动阶段只触发一次并随后解除武装。
    @MainActor
    func testPhaseWatchdogCancellationAndSingleFire() async {
        let watchdog = PTXP400BLEPhaseWatchdog(
            timeouts: PTXP400BLETimeouts(authentication: 0.01)
        )

        let canceledExpectation = expectation(description: "canceled watchdog stays silent")
        canceledExpectation.isInverted = true
        watchdog.arm(.authentication, timeout: 0.01) { _ in
            canceledExpectation.fulfill()
        }
        watchdog.cancel()
        await fulfillment(of: [canceledExpectation], timeout: 0.05)
        XCTAssertFalse(watchdog.isArmed)

        let firedExpectation = expectation(description: "active watchdog fires")
        watchdog.arm(.authentication, timeout: 0.01) { phase in
            XCTAssertEqual(phase, .authentication)
            firedExpectation.fulfill()
        }
        await fulfillment(of: [firedExpectation], timeout: 1)
        XCTAssertFalse(watchdog.isArmed)
    }
}
