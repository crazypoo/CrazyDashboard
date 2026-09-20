//
//  PTPitWallHTTP.swift
//  CrazyDashboard
//
//  EN: Minimal GET-only HTTP primitives for the local Pit Wall server.
//  ES: Primitivas HTTP mínimas y solo GET para el servidor local Pit Wall.
//  中文：Pit Wall 本地服务使用的最小 GET-only HTTP 基础设施。
//

import Foundation

public nonisolated struct PTPitWallHTTPRequest: Equatable, Sendable {
    public static let maximumRequestBytes = 16 * 1024

    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]

    public var token: String? {
        query["token"] ?? headers["x-pt-pitwall-token"]
    }

    public static func parse(_ data: Data) -> PTPitWallHTTPRequest? {
        guard data.count <= maximumRequestBytes,
              let string = String(data: data, encoding: .utf8),
              let headerEnd = string.range(of: "\r\n\r\n") else {
            return nil
        }

        let headerPart = String(string[..<headerEnd.lowerBound])
        let lines = headerPart.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[0].uppercased() == "GET",
              requestParts[2] == "HTTP/1.1",
              let components = URLComponents(string: "http://127.0.0.1\(requestParts[1])"),
              let path = components.path.isEmpty ? "/" : Optional(components.path),
              isAllowedPath(path) else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            headers[key] = value
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        return PTPitWallHTTPRequest(
            method: String(requestParts[0]),
            path: path,
            query: query,
            headers: headers
        )
    }

    private static func isAllowedPath(_ path: String) -> Bool {
        path == "/" || path == "/api/snapshot" || path == "/api/events"
    }
}

public nonisolated struct PTPitWallHTTPResponse: Sendable {
    public let statusCode: Int
    public let reason: String
    public let contentType: String
    public let body: Data
    public let headers: [String: String]

    public init(
        statusCode: Int,
        reason: String,
        contentType: String,
        body: Data,
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.reason = reason
        self.contentType = contentType
        self.body = body
        self.headers = headers
    }

    public func data() -> Data {
        var lines = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" }.sorted())
        lines.append("")
        lines.append("")

        var result = Data(lines.joined(separator: "\r\n").utf8)
        result.append(body)
        return result
    }

    public static func text(
        _ value: String,
        statusCode: Int = 200,
        reason: String = "OK"
    ) -> PTPitWallHTTPResponse {
        PTPitWallHTTPResponse(
            statusCode: statusCode,
            reason: reason,
            contentType: "text/plain; charset=utf-8",
            body: Data(value.utf8)
        )
    }

    public static func json(_ data: Data) -> PTPitWallHTTPResponse {
        PTPitWallHTTPResponse(
            statusCode: 200,
            reason: "OK",
            contentType: "application/json; charset=utf-8",
            body: data
        )
    }

    public static func unauthorized() -> PTPitWallHTTPResponse {
        text("Unauthorized", statusCode: 401, reason: "Unauthorized")
    }

    public static func notFound() -> PTPitWallHTTPResponse {
        text("Not Found", statusCode: 404, reason: "Not Found")
    }
}
