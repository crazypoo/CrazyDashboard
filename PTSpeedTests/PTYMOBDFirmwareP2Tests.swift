//
//  PTYMOBDFirmwareP2Tests.swift
//  PTSpeedTests
//
//  EN: Read-only YMOBD firmware preparation tests.
//  ES: Pruebas de preparación de firmware YMOBD de solo lectura.
//  中文：只读 YMOBD 固件准备流程测试。
//

import XCTest
@testable import XP400Ride

final class PTYMOBDFirmwareP2Tests: XCTestCase {
    func testProtocolTypeResolverMatchesDocumentedVersions() {
        XCTAssertEqual(PTYMOBDProtocolTypeResolver.resolve(atiResponse: "YMOBD v2.1"), 7)
        XCTAssertEqual(PTYMOBDProtocolTypeResolver.resolve(atiResponse: "YMOBD v3.0"), 9)
    }

    func testFirmwareMetadataDecoderSupportsNestedEnvelope() throws {
        let response = """
        {
          "code": "1",
          "data": {
            "firmwareVersion": "V2.4.0",
            "firmwareDesc": "XP400 compatibility",
            "firmwareFileUUID": "file-uuid-001",
            "pubKeyVer": 3,
            "fileSize": 2048
          }
        }
        """

        let metadata = try PTYMOBDFirmwareResponseDecoder.decodeMetadata(
            from: XCTUnwrap(response.data(using: .utf8))
        )
        XCTAssertEqual(metadata.firmwareVersion, "V2.4.0")
        XCTAssertEqual(metadata.firmwareDescription, "XP400 compatibility")
        XCTAssertEqual(metadata.firmwareFileUUID, "file-uuid-001")
        XCTAssertEqual(metadata.publicKeyVersion, 3)
        XCTAssertEqual(metadata.fileSize, 2048)
    }

    func testFirmwareVersionComparisonAvoidsFalseUpdate() {
        XCTAssertTrue(PTYMOBDFirmwareVersionComparator.isNewer("V2.4.1", than: "V2.4.0"))
        XCTAssertFalse(PTYMOBDFirmwareVersionComparator.isNewer("V2.4.0", than: "V2.4"))
        XCTAssertFalse(PTYMOBDFirmwareVersionComparator.isNewer("V1.9.9", than: "V2.0.0"))
    }

    func testFirmwareAPIBuildsDocumentedRequestsWithoutSendingThem() async throws {
        let configuration = PTYMOBDFirmwareAPIConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid/api"))
        )
        let api = PTYMOBDFirmwareAPI(configuration: configuration)
        let check = PTYMOBDFirmwareCheckRequest(
            deviceType: "YMOBD",
            protocolType: 9,
            obdFirmwareVersion: "V1.0.0"
        )
        let checkRequest = try await api.makeFirmwareCheckRequest(for: check)
        let checkComponents = try XCTUnwrap(URLComponents(url: XCTUnwrap(checkRequest.url), resolvingAgainstBaseURL: false))
        let checkItems = Dictionary(uniqueKeysWithValues: (checkComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(checkRequest.httpMethod, "GET")
        XCTAssertEqual(checkComponents.path, "/api/ymobd/client/getFirmwareLastVersionInfo")
        XCTAssertEqual(checkItems["deviceType"], "YMOBD")
        XCTAssertEqual(checkItems["protocolType"], "9")
        XCTAssertEqual(checkItems["obdFirmwareVersion"], "V1.0.0")

        let downloadRequest = try await api.makeFirmwareDownloadRequest(
            firmwareFileUUID: "file-uuid-001",
            encryptKey: String(repeating: "A", count: 512)
        )
        let downloadComponents = try XCTUnwrap(URLComponents(url: XCTUnwrap(downloadRequest.url), resolvingAgainstBaseURL: false))
        let downloadItems = Dictionary(uniqueKeysWithValues: (downloadComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(downloadComponents.path, "/api/ymobd/client/getFirmwareFile")
        XCTAssertEqual(downloadItems["firmwareFileUUID"], "file-uuid-001")
        XCTAssertEqual(downloadItems["encryptKey"], String(repeating: "A", count: 512))
    }

    func testFirmwareSecretUsesRSA2048AndUUIDShape() throws {
        let secret = try PTYMOBDFirmwareCrypto.createSecret()
        XCTAssertEqual(secret.publicKeyVersion, 3)
        XCTAssertEqual(secret.keyString.replacingOccurrences(of: "-", with: "").utf8.count, 32)
        XCTAssertEqual(secret.encryptKey.count, 512)
        XCTAssertTrue(secret.encryptKey.allSatisfy { "0123456789ABCDEF".contains($0) })
    }

    func testAES256OFBUsesTheDocumentedZeroIV() throws {
        let encrypted = try XCTUnwrap(Data(hexadecimal: "987a9e85cab88d05b4c720ad74f26186a698860907ae450fb64977"))
        let decrypted = try PTYMOBDFirmwareCrypto.decryptFirmware(
            encryptedData: encrypted,
            keyString: "550e8400-e29b-41d4-a716-446655440000"
        )
        XCTAssertEqual(
            decrypted,
            Data("Peugeot XP400 firmware test".utf8)
        )
    }
}

private extension Data {
    init?(hexadecimal: String) {
        let clean = hexadecimal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }
}
