//
//  PTXP400P3Tests.swift
//  PTSpeedTests
//
//  EN: P3 tests for the system ANCS boundary and experimental-provider lifecycle.
//  ES: Pruebas P3 para el límite ANCS del sistema y el ciclo de vida del proveedor experimental.
//  中文：覆盖系统 ANCS 边界和实验 Provider 生命周期的 P3 测试。
//

import XCTest
@testable import XP400Ride

final class PTXP400P3Tests: XCTestCase {
    func testSystemVerificationCoversCallSMSAndThirdPartyNotifications() {
        let sources = Set(PTXP400ANCSSystemPath.verificationCases.map(\.source))

        XCTAssertEqual(
            sources,
            Set([.phoneCall, .sms, .thirdPartyApp])
        )
        XCTAssertTrue(PTXP400ANCSSystemPath.verificationCases.allSatisfy { $0.channel == .system })
        XCTAssertTrue(PTXP400ANCSSystemPath.verificationCases.allSatisfy { $0.requiresRealPairedDevice })
    }

    func testSystemANCSActionsRemainSystemManaged() {
        for source in PTXP400ANCSNotificationSource.allCases {
            let verificationCase = PTXP400ANCSSystemPath.verificationCase(for: source)
            XCTAssertEqual(verificationCase.actionSupport, .systemManaged)
        }
    }

    func testExperimentalProviderIsExplicitlySeparatedFromSystemPath() {
        XCTAssertTrue(PTDashboardANCSProvider.isExperimental)
        XCTAssertEqual(PTXP400ANCSChannel.system.rawValue, "system")
        XCTAssertEqual(PTXP400ANCSChannel.experimentalCompatibility.rawValue, "experimentalCompatibility")
    }

    func testANCSServiceIdentifiersRemainTheConfirmedSystemShape() {
        XCTAssertEqual(
            PTDashboardANCSProvider.serviceUUID.uuidString.uppercased(),
            "7905F431-B5CE-4E99-A40F-4B1E122D00D0"
        )
        XCTAssertEqual(
            PTDashboardANCSProvider.notificationSourceUUID.uuidString.uppercased(),
            "9FBF120D-6301-42D9-8C58-25E699A21DBD"
        )
        XCTAssertEqual(
            PTDashboardANCSProvider.controlPointUUID.uuidString.uppercased(),
            "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9"
        )
        XCTAssertEqual(
            PTDashboardANCSProvider.dataSourceUUID.uuidString.uppercased(),
            "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB"
        )
    }
}
