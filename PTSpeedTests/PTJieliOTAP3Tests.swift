//
//  PTJieliOTAP3Tests.swift
//  CrazyDashboard
//
//  EN: Pure tests for the guarded Jieli OTA integration boundary.
//  ES: Pruebas puras para el límite protegido de integración OTA de Jieli.
//  中文：受保护的 Jieli OTA 集成边界的纯逻辑测试。
//

import XCTest
@testable import XP400Ride

final class PTJieliOTAP3Tests: XCTestCase {
    // EN: A normal Jieli layout must resolve AE01 as write and AE02 as notify when requested explicitly.
    // ES: Una disposición Jieli normal debe resolver AE01 como escritura y AE02 como notificación cuando se solicita explícitamente.
    // 中文：显式指定时，正常的 Jieli 布局应将 AE01 解析为写入、AE02 解析为通知。
    func testExplicitCharacteristicMapping() throws {
        let descriptors = [
            PTJieliCharacteristicDescriptor(
                uuid: "AE01",
                supportsWrite: true,
                supportsWriteWithoutResponse: false,
                supportsNotify: false,
                supportsIndicate: false
            ),
            PTJieliCharacteristicDescriptor(
                uuid: "0000AE02-0000-1000-8000-00805F9B34FB",
                supportsWrite: false,
                supportsWriteWithoutResponse: false,
                supportsNotify: true,
                supportsIndicate: false
            )
        ]

        let selection = try PTJieliCharacteristicResolver.resolve(
            descriptors: descriptors,
            mapping: .ae01WriteAE02Notify
        )

        XCTAssertEqual(selection.writeUUID, "AE01")
        XCTAssertEqual(selection.notifyUUID, "AE02")
    }

    // EN: Automatic mode refuses to guess when more than one characteristic can write or notify.
    // ES: El modo automático se niega a adivinar cuando hay más de una característica para escribir o notificar.
    // 中文：当可写或可通知特征超过一个时，自动模式必须拒绝猜测。
    func testAutomaticMappingRejectsAmbiguousRoles() {
        let descriptors = [
            PTJieliCharacteristicDescriptor(
                uuid: "AE01",
                supportsWrite: true,
                supportsWriteWithoutResponse: false,
                supportsNotify: true,
                supportsIndicate: false
            ),
            PTJieliCharacteristicDescriptor(
                uuid: "AE02",
                supportsWrite: true,
                supportsWriteWithoutResponse: false,
                supportsNotify: true,
                supportsIndicate: false
            )
        ]

        XCTAssertThrowsError(
            try PTJieliCharacteristicResolver.resolve(descriptors: descriptors)
        ) { error in
            XCTAssertEqual(error as? PTJieliCharacteristicResolverError, .ambiguousMapping)
        }
    }

    // EN: Explicit reverse layouts are accepted only when their properties support the requested roles.
    // ES: Las disposiciones invertidas explícitas solo se aceptan si sus propiedades admiten los roles solicitados.
    // 中文：只有特征属性确实支持对应角色时，显式反向布局才允许通过。
    func testReverseCharacteristicMappingValidatesProperties() throws {
        let descriptors = [
            PTJieliCharacteristicDescriptor(
                uuid: "AE01",
                supportsWrite: false,
                supportsWriteWithoutResponse: false,
                supportsNotify: true,
                supportsIndicate: false
            ),
            PTJieliCharacteristicDescriptor(
                uuid: "AE02",
                supportsWrite: true,
                supportsWriteWithoutResponse: false,
                supportsNotify: false,
                supportsIndicate: false
            )
        ]

        let selection = try PTJieliCharacteristicResolver.resolve(
            descriptors: descriptors,
            mapping: .ae02WriteAE01Notify
        )

        XCTAssertEqual(selection.writeUUID, "AE02")
        XCTAssertEqual(selection.notifyUUID, "AE01")
    }

    // EN: Progress is bounded before it reaches UI, persistence, or developer logs.
    // ES: El progreso se limita antes de llegar a la UI, la persistencia o los registros del desarrollador.
    // 中文：进度在进入界面、持久化或开发者日志前必须被限制在合法范围内。
    func testOTAProgressIsBounded() {
        let progress = PTOTAProgress(
            phase: 1,
            completedBytes: 150,
            totalBytes: 100,
            fractionCompleted: 2,
            detail: "  transfer  "
        )

        XCTAssertEqual(progress.phase, 1)
        XCTAssertEqual(progress.completedBytes, 100)
        XCTAssertEqual(progress.totalBytes, 100)
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertEqual(progress.detail, "transfer")
    }

    // EN: The session records transfer metadata without persisting firmware bytes.
    // ES: La sesión registra metadatos de transferencia sin persistir bytes del firmware.
    // 中文：会话只记录传输元数据，不持久化固件字节。
    func testOTASessionNormalizesMetadata() {
        let session = PTOTASession(
            deviceIdentifier: "  device-id  ",
            deviceName: "  XP400  ",
            oldFirmwareVersion: "  old  ",
            targetFirmwareVersion: " target ",
            firmwareFileUUID: " file ",
            firmwareByteCount: -1,
            firmwareSHA256: " abcd "
        )

        XCTAssertEqual(session.deviceIdentifier, "device-id")
        XCTAssertEqual(session.deviceName, "XP400")
        XCTAssertEqual(session.oldFirmwareVersion, "old")
        XCTAssertEqual(session.targetFirmwareVersion, "target")
        XCTAssertEqual(session.firmwareFileUUID, "file")
        XCTAssertEqual(session.firmwareByteCount, 0)
        XCTAssertEqual(session.firmwareSHA256, "ABCD")
    }
}
