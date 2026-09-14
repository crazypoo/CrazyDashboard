//
//  PTYMOBDFirmwareAPI.swift
//  CrazyDashboard
//
//  EN: Provides the documented YMOBD firmware-check and encrypted-download APIs.
//  ES: Proporciona las API documentadas de comprobación y descarga cifrada de firmware YMOBD.
//  中文：提供文档中的 YMOBD 固件检查和加密下载 API。
//

import Foundation
import OSLog

nonisolated public struct PTYMOBDFirmwareAPIConfiguration: Sendable {
    public let baseURL: URL
    public let firmwareInfoPath: String
    public let firmwareFilePath: String
    public let requestTimeout: TimeInterval
    public let maximumMetadataBytes: Int

    public init(
        baseURL: URL,
        firmwareInfoPath: String = "/ymobd/client/getFirmwareLastVersionInfo",
        firmwareFilePath: String = "/ymobd/client/getFirmwareFile",
        requestTimeout: TimeInterval = 20,
        maximumMetadataBytes: Int = 1 * 1024 * 1024
    ) {
        self.baseURL = baseURL
        self.firmwareInfoPath = firmwareInfoPath
        self.firmwareFilePath = firmwareFilePath
        self.requestTimeout = max(requestTimeout, 1)
        self.maximumMetadataBytes = max(maximumMetadataBytes, 1)
    }

    // EN: Load the optional developer endpoint from Info.plist; production builds never receive a guessed server URL.
    // ES: Carga el endpoint opcional de desarrollador desde Info.plist; las compilaciones de producción nunca adivinan una URL.
    // 中文：从 Info.plist 读取可选的开发者服务地址；生产版本不会猜测或内置服务 URL。
    public static func fromMainBundle(_ bundle: Bundle = .main) -> PTYMOBDFirmwareAPIConfiguration? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "YMOBDFirmwareAPIBaseURL") as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }
        return PTYMOBDFirmwareAPIConfiguration(baseURL: url)
    }
}

nonisolated public enum PTYMOBDFirmwareAPIError: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest
    case invalidBaseURL
    case invalidHTTPResponse
    case serverStatus(Int)
    case metadataResponseTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "固件请求参数无效"
        case .invalidBaseURL:
            return "固件服务地址无效"
        case .invalidHTTPResponse:
            return "固件服务返回不是 HTTP 响应"
        case let .serverStatus(status):
            return "固件检查服务返回 HTTP \(status)"
        case let .metadataResponseTooLarge(maximumBytes):
            return "固件元数据响应超过限制（\(maximumBytes) bytes）"
        }
    }
}

public actor PTYMOBDFirmwareAPI {
    public static let defaultFirmwareInfoPath = "/ymobd/client/getFirmwareLastVersionInfo"
    public static let defaultFirmwareFilePath = "/ymobd/client/getFirmwareFile"

    private let configuration: PTYMOBDFirmwareAPIConfiguration
    private let session: URLSession
    private let downloader: PTYMOBDFirmwareDownloader
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "YMOBD.FirmwareAPI")

    public init(
        configuration: PTYMOBDFirmwareAPIConfiguration,
        session: URLSession = .shared,
        downloader: PTYMOBDFirmwareDownloader? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.downloader = downloader ?? PTYMOBDFirmwareDownloader(session: session)
    }

    public func makeFirmwareCheckRequest(
        for request: PTYMOBDFirmwareCheckRequest
    ) throws -> URLRequest {
        guard request.isValid else {
            throw PTYMOBDFirmwareAPIError.invalidRequest
        }

        let serverFirmwareVersion = try serverFirmwareVersion(for: request)

        let url = try makeURL(
            path: configuration.firmwareInfoPath,
            queryItems: []
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.requestTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "deviceType": request.deviceType,
            "protocolType": String(request.protocolType),
            "obdFirmwareVersion": serverFirmwareVersion
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw PTYMOBDFirmwareAPIError.invalidRequest
        }
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw PTYMOBDFirmwareAPIError.invalidRequest
        }
        return urlRequest
    }

    public func makeFirmwareDownloadRequest(
        firmwareFileUUID: String,
        encryptKey: String
    ) throws -> URLRequest {
        let fileUUID = firmwareFileUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = encryptKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileUUID.isEmpty,
              key.count == 512,
              key.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else {
            throw PTYMOBDFirmwareAPIError.invalidRequest
        }

        let url = try makeURL(
            path: configuration.firmwareFilePath,
            queryItems: [
                URLQueryItem(name: "firmwareFileUUID", value: fileUUID),
                URLQueryItem(name: "encryptKey", value: key)
            ]
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = configuration.requestTimeout
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        return urlRequest
    }

    public func checkLatestFirmware(
        for request: PTYMOBDFirmwareCheckRequest
    ) async throws -> PTYMOBDFirmwareCheckResult {
        let urlRequest = try makeFirmwareCheckRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PTYMOBDFirmwareAPIError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PTYMOBDFirmwareAPIError.serverStatus(httpResponse.statusCode)
        }
        guard data.count <= configuration.maximumMetadataBytes else {
            throw PTYMOBDFirmwareAPIError.metadataResponseTooLarge(
                maximumBytes: configuration.maximumMetadataBytes
            )
        }

        let metadata = try PTYMOBDFirmwareResponseDecoder.decodeMetadata(from: data)
        let result = PTYMOBDFirmwareCheckResult(request: request, metadata: metadata)
        logger.info("YMOBD firmware metadata received: version=\(metadata.firmwareVersion, privacy: .public), updateAvailable=\(result.isUpdateAvailable, privacy: .public)")
        return result
    }

    public func downloadEncryptedFirmware(
        firmwareFileUUID: String,
        encryptKey: String
    ) async throws -> PTYMOBDFirmwareDownloadedArtifact {
        let request = try makeFirmwareDownloadRequest(
            firmwareFileUUID: firmwareFileUUID,
            encryptKey: encryptKey
        )
        return try await downloader.download(request: request)
    }
}

private extension PTYMOBDFirmwareAPI {
    // EN: The live YMOBD endpoint requires a decimal integer for the current firmware version; never invent a conversion for semantic labels.
    // ES: El endpoint YMOBD real requiere un entero decimal para la versión actual; nunca inventamos una conversión para etiquetas semánticas.
    // 中文：真实 YMOBD 接口要求当前固件版本为十进制整数；不为语义化版本号擅自猜测转换规则。
    func serverFirmwareVersion(for request: PTYMOBDFirmwareCheckRequest) throws -> Int {
        let value = request.obdFirmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version = Int(value), version >= 0 else {
            throw PTYMOBDFirmwareAPIError.invalidRequest
        }
        return version
    }

    func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard let baseComponents = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ),
        let scheme = baseComponents.scheme?.lowercased(),
        ["http", "https"].contains(scheme),
        baseComponents.host != nil else {
            throw PTYMOBDFirmwareAPIError.invalidBaseURL
        }

        var components = baseComponents
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let endpointPath = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + endpointPath
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PTYMOBDFirmwareAPIError.invalidBaseURL
        }
        return url
    }
}
