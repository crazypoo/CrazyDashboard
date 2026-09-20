//
//  PTPitWallBuild84Tests.swift
//  PTSpeedTests
//
//  EN: Pure safety, privacy and bounded-storage tests for Build 84.
//  ES: Pruebas puras de seguridad, privacidad y almacenamiento acotado para Build 84.
//  中文：Build 84 的安全、隐私和有界存储纯逻辑测试。
//

import XCTest
@testable import XP400Ride

final class PTPitWallBuild84Tests: XCTestCase {
    func testRollingSeriesKeepsOnlyLatestSixtySamples() {
        var series = PTPitWallRollingSeries(maximumCount: 60)
        for index in 0..<75 {
            series.append(
                PTPitWallSample(
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    speedKmh: Double(index),
                    rpm: index,
                    coordinate: nil
                )
            )
        }

        XCTAssertEqual(series.samples.count, 60)
        XCTAssertEqual(series.samples.first?.rpm, 15)
        XCTAssertEqual(series.samples.last?.rpm, 74)
    }

    func testHTTPParserAcceptsGETAndCaseInsensitiveTokenHeader() {
        let request = Data("GET /api/snapshot HTTP/1.1\r\nx-PT-PitWall-Token: abc123\r\nHost: local\r\n\r\n".utf8)

        let parsed = PTPitWallHTTPRequest.parse(request)

        XCTAssertEqual(parsed?.method, "GET")
        XCTAssertEqual(parsed?.path, "/api/snapshot")
        XCTAssertEqual(parsed?.token, "abc123")
    }

    func testHTTPParserRejectsPOSTOversizeAndUnknownPath() {
        let post = Data("POST /api/snapshot HTTP/1.1\r\n\r\n".utf8)
        let unknown = Data("GET /write HTTP/1.1\r\n\r\n".utf8)
        let oversize = Data(repeating: 65, count: PTPitWallHTTPRequest.maximumRequestBytes + 1)

        XCTAssertNil(PTPitWallHTTPRequest.parse(post))
        XCTAssertNil(PTPitWallHTTPRequest.parse(unknown))
        XCTAssertNil(PTPitWallHTTPRequest.parse(oversize))
    }

    func testSerializerRoundsCoordinatesAndExcludesVehicleIdentity() throws {
        let snapshot = PTPitWallSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            dashboardConnected: true,
            obdConnected: false,
            context: "riding",
            speedKmh: 88.876,
            rpm: 5_500,
            fuelPercent: 72.345,
            voltage: 13.876,
            leanDegrees: 12.345,
            tcsState: "mode1",
            absState: "ready",
            kickstandDown: false,
            engineState: "running",
            freshness: "fresh",
            isSynthetic: false,
            coordinate: PTPitWallCoordinate(latitude: 37.1234567, longitude: 121.9876543),
            samples: [],
            events: []
        )

        let data = try PTPitWallSnapshotSerializer.data(from: snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertTrue(json.contains("37.12346"))
        XCTAssertFalse(json.contains("VIN"))
        XCTAssertFalse(json.contains("centralIdentifier"))
        XCTAssertFalse(json.contains("rawHex"))
        XCTAssertFalse(json.contains("errorMessage"))
    }

    func testEmbeddedWebUIHasCSPAndNoExternalDependency() {
        let html = String(decoding: PTPitWallWebUI.html(token: "token123"), as: UTF8.self)

        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("token123"))
        XCTAssertTrue(html.contains("/api/snapshot"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<script src="))
    }

    func testHTTPResponseContainsCorrectLengthAndNoStore() {
        let response = PTPitWallHTTPResponse.text("OK")
        let output = String(decoding: response.data(), as: UTF8.self)

        XCTAssertTrue(output.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(output.contains("Content-Length: 2"))
        XCTAssertTrue(output.contains("Cache-Control: no-store"))
    }
}
