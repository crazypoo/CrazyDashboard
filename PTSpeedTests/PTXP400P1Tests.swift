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
