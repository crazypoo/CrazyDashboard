//
//  PTLyricsService.swift
//  CrazyDashboard
//
//  EN: Resolves embedded lyrics first and uses an opt-in LRCLIB fallback.
//  ES: Resuelve primero las letras incrustadas y usa un respaldo LRCLIB con consentimiento.
//  中文：优先解析歌曲内嵌歌词，并在用户同意后使用 LRCLIB 作为回退来源。
//

import Foundation

public nonisolated struct PTNowPlayingTrackSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let embeddedLyrics: String?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        embeddedLyrics: String?
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.embeddedLyrics = embeddedLyrics
    }
}

public nonisolated struct PTLyricLine: Codable, Equatable, Sendable {
    public let startTime: TimeInterval?
    public let text: String

    public init(startTime: TimeInterval?, text: String) {
        self.startTime = startTime
        self.text = text
    }
}

public nonisolated enum PTLyricsSource: String, Codable, Sendable {
    case embedded
    case lrclib
}

public nonisolated struct PTLyricsDocument: Codable, Equatable, Sendable {
    public let source: PTLyricsSource
    public let lines: [PTLyricLine]
    public let isInstrumental: Bool

    public init(source: PTLyricsSource, lines: [PTLyricLine], isInstrumental: Bool = false) {
        self.source = source
        self.lines = lines
        self.isInstrumental = isInstrumental
    }

    public var isSynced: Bool {
        lines.contains { $0.startTime != nil }
    }
}

enum PTLyricsDisplayState: Equatable {
    case idle
    case loading
    case available
    case instrumental
    case onlineLookupDisabled
    case noMatch
    case permissionDenied
    case failed
}

enum PTLyricsSettings {
    static let onlineLookupEnabledKey = "lyrics_online_lookup_enabled"
    static let consentPromptedKey = "lyrics_online_lookup_consent_prompted"

    static var onlineLookupEnabled: Bool {
        UserDefaults.standard.bool(forKey: onlineLookupEnabledKey)
    }

    static var consentPrompted: Bool {
        UserDefaults.standard.bool(forKey: consentPromptedKey)
    }

    static func setOnlineLookupEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: onlineLookupEnabledKey)
        UserDefaults.standard.set(true, forKey: consentPromptedKey)
    }
}

public nonisolated enum PTLyricsParser {
    // EN: Parse standard LRC timestamps without treating metadata tags as lyric text.
    // ES: Analiza marcas de tiempo LRC estándar sin tratar las etiquetas de metadatos como letras.
    // 中文：解析标准 LRC 时间戳，并避免把元数据标签当成歌词内容。
    public static func parseSynced(_ text: String) -> [PTLyricLine]? {
        var offsetMilliseconds = 0.0
        var parsedLines: [PTLyricLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            var remaining = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            var timestamps: [TimeInterval] = []

            while remaining.hasPrefix("[") {
                guard let closingBracket = remaining.firstIndex(of: "]") else { break }
                let tagStart = remaining.index(after: remaining.startIndex)
                let tag = String(remaining[tagStart..<closingBracket])
                remaining = String(remaining[remaining.index(after: closingBracket)...])

                if tag.lowercased().hasPrefix("offset:") {
                    let value = tag.dropFirst("offset:".count)
                    if let parsedOffset = Double(String(value).trimmingCharacters(in: .whitespaces)) {
                        offsetMilliseconds = parsedOffset
                    }
                } else if let timestamp = parseTimestamp(tag) {
                    timestamps.append(timestamp)
                }
            }

            guard !timestamps.isEmpty else { continue }
            let lyricText = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }

            for timestamp in timestamps {
                let adjustedTime = max(0, timestamp + offsetMilliseconds / 1_000)
                parsedLines.append(PTLyricLine(startTime: adjustedTime, text: lyricText))
            }
        }

        let sortedLines = parsedLines.sorted {
            let lhs = $0.startTime ?? 0
            let rhs = $1.startTime ?? 0
            if lhs == rhs { return $0.text < $1.text }
            return lhs < rhs
        }

        var uniqueLines: [PTLyricLine] = []
        var seen = Set<String>()
        for line in sortedLines {
            let key = "\(line.startTime ?? 0)|\(line.text)"
            guard seen.insert(key).inserted else { continue }
            uniqueLines.append(line)
        }
        return uniqueLines.isEmpty ? nil : uniqueLines
    }

    public static func parsePlain(_ text: String) -> [PTLyricLine] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { PTLyricLine(startTime: nil, text: $0) }
    }

    private static func parseTimestamp(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
              minutes >= 0,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }
        return minutes * 60 + seconds
    }
}

public nonisolated enum PTLyricsError: LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case notFound
    case rateLimited(TimeInterval?)
    case server(statusCode: Int)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Invalid lyrics request"
        case .invalidResponse: return "Invalid lyrics response"
        case .responseTooLarge: return "Lyrics response is too large"
        case .notFound: return "Lyrics not found"
        case .rateLimited: return "Lyrics service is rate limited"
        case .server(let statusCode): return "Lyrics service returned HTTP \(statusCode)"
        case .transport(let message): return message
        }
    }
}

public actor PTLyricsService {
    public static let shared = PTLyricsService()

    private struct LRCLIBResponse: Decodable, Sendable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let session: URLSession
    private var cache: [String: PTLyricsDocument] = [:]
    private var cacheOrder: [String] = []
    private var negativeCache: [String: Date] = [:]
    private var retryUntil: Date?

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 8
            configuration.httpMaximumConnectionsPerHost = 2
            self.session = URLSession(configuration: configuration)
        }
    }

    public func lyrics(
        for snapshot: PTNowPlayingTrackSnapshot,
        allowOnlineLookup: Bool
    ) async throws -> PTLyricsDocument? {
        let cacheKey = snapshot.id

        if let cached = cache[cacheKey] {
            return cached
        }

        if let embeddedLyrics = snapshot.embeddedLyrics,
           let document = makeDocument(
               source: .embedded,
               plainLyrics: embeddedLyrics,
               syncedLyrics: embeddedLyrics,
               instrumental: false
           ) {
            store(document, for: cacheKey)
            return document
        }

        guard allowOnlineLookup else { return nil }
        guard !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let negativeDate = negativeCache[cacheKey], Date().timeIntervalSince(negativeDate) < 600 {
            return nil
        }
        if let retryUntil, retryUntil > Date() {
            throw PTLyricsError.rateLimited(retryUntil.timeIntervalSinceNow)
        }

        var exactResponse: LRCLIBResponse?
        do {
            exactResponse = try await requestExact(for: snapshot)
        } catch PTLyricsError.notFound {
            exactResponse = nil
        }

        if let exactResponse,
           matches(exactResponse, snapshot: snapshot),
           let document = makeDocument(from: exactResponse, source: .lrclib) {
            store(document, for: cacheKey)
            return document
        }

        let searchResults = try await requestSearch(for: snapshot)
        guard let matchedResponse = selectMatch(from: searchResults, snapshot: snapshot),
              let document = makeDocument(from: matchedResponse, source: .lrclib) else {
            negativeCache[cacheKey] = Date()
            return nil
        }

        store(document, for: cacheKey)
        return document
    }

    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        negativeCache.removeAll(keepingCapacity: true)
        retryUntil = nil
    }

    private func requestExact(for snapshot: PTNowPlayingTrackSnapshot) async throws -> LRCLIBResponse {
        let url = try makeURL(
            path: "/api/get",
            queryItems: queryItems(for: snapshot, includeDuration: true)
        )
        return try await request(url: url, as: LRCLIBResponse.self)
    }

    private func requestSearch(for snapshot: PTNowPlayingTrackSnapshot) async throws -> [LRCLIBResponse] {
        let url = try makeURL(
            path: "/api/search",
            queryItems: queryItems(for: snapshot, includeDuration: false)
        )
        return try await request(url: url, as: [LRCLIBResponse].self)
    }

    private func queryItems(
        for snapshot: PTNowPlayingTrackSnapshot,
        includeDuration: Bool
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: snapshot.title),
            URLQueryItem(name: "artist_name", value: snapshot.artist)
        ]
        if !snapshot.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: snapshot.album))
        }
        if includeDuration, snapshot.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(format: "%.0f", snapshot.duration)))
        }
        return items
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(string: "https://lrclib.net\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw PTLyricsError.invalidRequest }
        return url
    }

    private func request<T: Decodable>(url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(
            "XP400Ride/2.0.8 (https://github.com/crazypoo/CrazyDashboard)",
            forHTTPHeaderField: "Lrclib-Client"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PTLyricsError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PTLyricsError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 404:
            throw PTLyricsError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            if let retryAfter {
                retryUntil = Date().addingTimeInterval(max(1, retryAfter))
            } else {
                retryUntil = Date().addingTimeInterval(60)
            }
            throw PTLyricsError.rateLimited(retryAfter)
        default:
            throw PTLyricsError.server(statusCode: httpResponse.statusCode)
        }

        guard data.count <= 512 * 1024 else {
            throw PTLyricsError.responseTooLarge
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PTLyricsError.invalidResponse
        }
    }

    private func makeDocument(
        source: PTLyricsSource,
        plainLyrics: String?,
        syncedLyrics: String?,
        instrumental: Bool
    ) -> PTLyricsDocument? {
        if instrumental {
            return PTLyricsDocument(source: source, lines: [], isInstrumental: true)
        }

        if let syncedLyrics,
           let lines = PTLyricsParser.parseSynced(syncedLyrics) {
            return PTLyricsDocument(source: source, lines: lines)
        }

        guard let plainLyrics else { return nil }
        let lines = PTLyricsParser.parsePlain(plainLyrics)
        return lines.isEmpty ? nil : PTLyricsDocument(source: source, lines: lines)
    }

    private func makeDocument(
        from response: LRCLIBResponse,
        source: PTLyricsSource
    ) -> PTLyricsDocument? {
        makeDocument(
            source: source,
            plainLyrics: response.plainLyrics,
            syncedLyrics: response.syncedLyrics,
            instrumental: response.instrumental ?? false
        )
    }

    private func matches(
        _ response: LRCLIBResponse,
        snapshot: PTNowPlayingTrackSnapshot
    ) -> Bool {
        guard let trackName = response.trackName,
              let artistName = response.artistName,
              normalize(trackName) == normalize(snapshot.title),
              normalize(artistName) == normalize(snapshot.artist),
              snapshot.duration > 0,
              let duration = response.duration else {
            return false
        }
        return abs(duration - snapshot.duration) <= 3
    }

    private func selectMatch(
        from responses: [LRCLIBResponse],
        snapshot: PTNowPlayingTrackSnapshot
    ) -> LRCLIBResponse? {
        let matches = responses.filter { matches($0, snapshot: snapshot) }
        guard !matches.isEmpty else { return nil }
        guard matches.count > 1 else { return matches[0] }

        let albumMatches = matches.filter {
            guard let albumName = $0.albumName, !snapshot.album.isEmpty else { return false }
            return normalize(albumName) == normalize(snapshot.album)
        }
        return albumMatches.count == 1 ? albumMatches[0] : nil
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func store(_ document: PTLyricsDocument, for key: String) {
        cache[key] = document
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 20 {
            let oldestKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
    }
}
