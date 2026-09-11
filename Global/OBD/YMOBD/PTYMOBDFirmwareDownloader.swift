//
//  PTYMOBDFirmwareDownloader.swift
//  CrazyDashboard
//
//  EN: Downloads encrypted firmware for inspection only; it has no OTA transport.
//  ES: Descarga firmware cifrado solo para inspección; no contiene transporte OTA.
//  中文：只下载用于检查的加密固件，不包含任何 OTA 传输。
//

import Foundation
import CryptoKit
import OSLog

public struct PTYMOBDFirmwareDownloadedArtifact: Sendable {
    public let data: Data
    public let byteCount: Int
    public let sha256Hex: String

    public init(data: Data) {
        self.data = data
        self.byteCount = data.count
        self.sha256Hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum PTYMOBDFirmwareDownloadError: Error, Equatable, LocalizedError, Sendable {
    case invalidHTTPResponse
    case serverStatus(Int)
    case emptyPayload
    case payloadTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "固件服务返回不是 HTTP 响应"
        case let .serverStatus(status):
            return "固件下载服务返回 HTTP \(status)"
        case .emptyPayload:
            return "固件下载内容为空"
        case let .payloadTooLarge(maximumBytes):
            return "固件下载内容超过限制（\(maximumBytes) bytes）"
        }
    }
}

public actor PTYMOBDFirmwareDownloader {
    public static let defaultMaximumFileSize = 64 * 1024 * 1024

    private let session: URLSession
    private let maximumFileSize: Int
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "YMOBD.Firmware")

    public init(
        session: URLSession = .shared,
        maximumFileSize: Int = PTYMOBDFirmwareDownloader.defaultMaximumFileSize
    ) {
        self.session = session
        self.maximumFileSize = max(maximumFileSize, 1)
    }

    // EN: Keep this request bounded and report only size/hash metadata, never keys or firmware bytes.
    // ES: Mantiene la solicitud acotada y registra solo tamaño/hash, nunca claves ni bytes del firmware.
    // 中文：限制下载大小，并且只记录大小与哈希，绝不记录密钥或固件内容。
    public func download(request: URLRequest) async throws -> PTYMOBDFirmwareDownloadedArtifact {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PTYMOBDFirmwareDownloadError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PTYMOBDFirmwareDownloadError.serverStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw PTYMOBDFirmwareDownloadError.emptyPayload
        }
        guard data.count <= maximumFileSize else {
            throw PTYMOBDFirmwareDownloadError.payloadTooLarge(maximumBytes: maximumFileSize)
        }

        let artifact = PTYMOBDFirmwareDownloadedArtifact(data: data)
        logger.info("YMOBD encrypted firmware received: bytes=\(artifact.byteCount, privacy: .public), sha256=\(artifact.sha256Hex, privacy: .public)")
        return artifact
    }
}
