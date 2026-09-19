//
//  PTVehicleTwin3DTests.swift
//  PTSpeedTests
//
//  EN: Contract tests for the Build 76B renderer boundary and asset manifest.
//  ES: Pruebas de contrato para el límite del renderer y el manifest de Build 76B.
//  中文：Build 76B 渲染器边界和资源清单的契约测试。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTVehicleTwin3DTests: XCTestCase {
    func testDisplayModesAndCameraPresetsAreStable() {
        XCTAssertEqual(PTVehicleTwinDisplayMode.allCases, [.automatic, .twoD, .threeD])
        XCTAssertEqual(PTVehicleTwin3DCameraPreset.allCases.count, 6)
        XCTAssertEqual(PTVehicleTwin3DCameraPreset.allCases, [.front, .rear, .left, .right, .top, .follow])
    }

    func testAssetManifestKeepsIndependentAnimatedNodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "source": "test",
          "coordinateSystem": "x=front, y=up, z=left",
          "modelNames": ["xp400", "xp400_gt"],
          "requiredNodeNames": [
            "xp400.root",
            "xp400.body",
            "xp400.frontWheel.pivot",
            "xp400.rearWheel.pivot",
            "xp400.light.headlight",
            "xp400.light.brake",
            "xp400.light.indicator.left",
            "xp400.light.indicator.right",
            "xp400.kickstand.pivot",
            "xp400.rpm.indicator",
            "xp400.motion.gVector"
          ],
          "wheelRadiusMeters": 0.34,
          "maximumTriangleCount": 2400,
          "maximumMaterialCount": 8,
          "usesExternalTextures": false
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PTVehicleTwin3DAssetManifest.self, from: json)

        XCTAssertEqual(manifest.modelNames, ["xp400", "xp400_gt"])
        XCTAssertEqual(manifest.requiredNodeNames, PTVehicleTwin3DNodeName.required)
        XCTAssertFalse(manifest.usesExternalTextures)
        XCTAssertLessThanOrEqual(manifest.maximumTriangleCount, 2400)
    }

    func testPerformancePolicyFallsBackOnlyForPowerOrThermalPressure() {
        XCTAssertEqual(
            PTVehicleTwin3DPerformancePolicy.fallbackReason(
                lowPowerModeEnabled: true,
                thermalState: .nominal
            ),
            .lowPowerMode
        )
        XCTAssertEqual(
            PTVehicleTwin3DPerformancePolicy.fallbackReason(
                lowPowerModeEnabled: false,
                thermalState: .serious
            ),
            .thermalPressure
        )
        XCTAssertNil(
            PTVehicleTwin3DPerformancePolicy.fallbackReason(
                lowPowerModeEnabled: false,
                thermalState: .nominal
            )
        )
    }
}
