//
//  PTXP400BLEP0Fixtures.swift
//  CrazyDashboard
//
//  EN: Stable protocol vectors used to guard the existing XP400 BLE behavior.
//  ES: Vectores de protocolo estables para proteger el comportamiento BLE existente del XP400.
//  中文：用于保护现有 XP400 BLE 行为的稳定协议向量。
//

import Foundation
@testable import XP400Ride

/// EN: These are deterministic samples only; no vehicle identity or secret lookup table is stored here.
/// ES: Son muestras deterministas; aquí no se guarda identidad del vehículo ni la tabla secreta.
/// 中文：这些仅是确定性样本，不保存车辆身份或认证密钥表。
enum PTXP400BLEP0Fixtures {
    static let dashboardKeyConfiguration = Data([
        0x00, 0x00, 0x22, 0x36,
        0x02, 0x00, 0x08,
        0x01, 0x04, 0x25,
        0x01, 0x17, 0x09, 0x00, 0x00
    ])

    static let firstChallenge = Data([
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
        0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13
    ])

    // EN: The first ten response bytes are deterministic for UInt16 values 0...9; the trailing ten bytes are intentionally random.
    // ES: Los primeros diez bytes son deterministas para los UInt16 0...9; los diez finales son intencionadamente aleatorios.
    // 中文：对 UInt16 0...9 而言，响应前 10 字节是确定的，后 10 字节按协议故意随机。
    static let firstResponsePrefix = Data([
        0xD9, 0xC9, 0x0A, 0x4B, 0x0E,
        0x46, 0x36, 0x33, 0x2C, 0x66
    ])

    static let secondChallenge = Data([
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19,
        0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23
    ])

    static let connectionFrame = Data([0x16, 0x01])
        + Data("A1B2C3D4E5F6".utf8)
        + Data([0x00])

    static let fullCreditGrant = Data([0x19])

    static let data1Frame = Data([
        0x16, 0x02,
        0xFE, 0x00, 0x2D, 0x04, 0xE2, 0x00, 0x00, 0x0A,
        0x00
    ])

    static let data2Frame = Data([
        0x16, 0x03,
        0x00, 0x02, 0x00, 0x00, 0x55, 0x8E, 0x00, 0x00,
        0x00
    ])

    static let data3Frame = Data([
        0x16, 0x04,
        0x09, 0xC4, 0x80, 0x04, 0x4C, 0x02, 0x00, 0x00,
        0x00
    ])

    static let absFrame = Data([
        0x16, 0x06,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00
    ])

    static let navigationInfo = PTNavigationInfo(
        nextManeuver: PTManeuverMap.lightRight,
        metersToNextManeuver: 125,
        nameNextRoad: "Rue de Lyon",
        nameCurrentRoad: "Route 1",
        currentSpeedLimit: 50,
        distanceToDestination: 2_310,
        estimatedTimeToDestinationSec: 120
    )
}
