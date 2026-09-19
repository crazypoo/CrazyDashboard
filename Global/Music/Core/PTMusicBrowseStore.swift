//
//  PTMusicBrowseStore.swift
//  CrazyDashboard
//
//  English: Main-actor orchestration for browsing, searching, caching and paging.
//  Español: Orquestación en el actor principal para navegar, buscar, cachear y paginar.
//  中文：在主 actor 上统一协调浏览、搜索、缓存、分页和请求生命周期。
//

import Combine
import Foundation
import MusicKit

public nonisolated protocol PTMusicLibraryServing: Sendable {
    func songs(limit: Int, offset: Int) async throws -> [Song]
    func albums(limit: Int, offset: Int) async throws -> [Album]
    func artists(limit: Int, offset: Int) async throws -> [Artist]
    func playlists(limit: Int, offset: Int) async throws -> [Playlist]
    func recentlyPlayedSongs(limit: Int) async throws -> [Song]
}

public nonisolated protocol PTMusicCatalogServing: Sendable {
    func searchSongs(term: String, limit: Int) async throws -> [Song]
    func searchAlbums(term: String, limit: Int) async throws -> [Album]
    func searchArtists(term: String, limit: Int) async throws -> [Artist]
    func searchPlaylists(term: String, limit: Int) async throws -> [Playlist]
}

public nonisolated protocol PTMusicCollectionServing: Sendable {
    func loadAlbum(_ album: Album) async throws -> Album
    func loadPlaylist(_ playlist: Playlist) async throws -> Playlist
    func loadArtist(_ artist: Artist) async throws -> Artist
}

@MainActor
public protocol PTMusicAuthorizationProviding: AnyObject {
    var authorizationStatus: MusicAuthorization.Status { get }
    var subscription: MusicSubscription? { get }
    var hasCloudLibraryEnabled: Bool { get }
    func refreshAuthorizationStatus()
    func requestAuthorization() async -> MusicAuthorization.Status
    func refreshSubscription() async
}

extension PTMusicAuthorizationManager: PTMusicAuthorizationProviding {}

@MainActor
public final class PTMusicBrowseStore: ObservableObject {

    private struct CacheEntry {
        let payload: PTMusicBrowsePayload
        let pageState: PTMusicPageState
        let loadedAt: Date
    }

    public let cachePolicy: PTMusicBrowseCachePolicy

    @Published public private(set) var state: PTMusicLoadState = .idle
    @Published public private(set) var payload: PTMusicBrowsePayload?
    @Published public private(set) var pageState: PTMusicPageState?
    @Published public private(set) var currentQueryKey: PTMusicQueryKey?

    private let libraryService: any PTMusicLibraryServing
    private let catalogService: any PTMusicCatalogServing
    private let authorization: any PTMusicAuthorizationProviding
    private let now: @Sendable () -> Date
    private let requestTimeout: TimeInterval

    private var cache: [PTMusicQueryKey: CacheEntry] = [:]
    private var cacheAccessOrder: [PTMusicQueryKey] = []
    private var generation: UInt64 = 0
    private var requestID: UUID?
    private var requestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init(
        libraryService: any PTMusicLibraryServing,
        catalogService: any PTMusicCatalogServing,
        authorization: any PTMusicAuthorizationProviding,
        cachePolicy: PTMusicBrowseCachePolicy,
        requestTimeout: TimeInterval,
        now: @escaping @Sendable () -> Date
    ) {
        self.libraryService = libraryService
        self.catalogService = catalogService
        self.authorization = authorization
        self.cachePolicy = cachePolicy
        self.requestTimeout = max(1, requestTimeout)
        self.now = now
    }

    public convenience init() {
        self.init(
            libraryService: PTMusicLibraryService.shared,
            catalogService: PTMusicCatalogService.shared,
            authorization: PTMusicAuthorizationManager.shared,
            cachePolicy: PTMusicBrowseCachePolicy(),
            requestTimeout: 15,
            now: Date.init
        )
    }

    public convenience init(
        libraryService: any PTMusicLibraryServing,
        catalogService: any PTMusicCatalogServing,
        authorization: any PTMusicAuthorizationProviding,
        requestTimeout: TimeInterval = 15
    ) {
        self.init(
            libraryService: libraryService,
            catalogService: catalogService,
            authorization: authorization,
            cachePolicy: PTMusicBrowseCachePolicy(),
            requestTimeout: requestTimeout,
            now: Date.init
        )
    }

    deinit {
        requestTask?.cancel()
        debounceTask?.cancel()
        timeoutTask?.cancel()
    }

    public var cachedQueryCount: Int {
        cache.count
    }

    public func selectLibrary(
        source: PTMusicSource,
        category: PTMusicBrowseCategory,
        forceRefresh: Bool = false
    ) {
        let normalizedSource = source == .recentlyPlayed ? source : .library
        let key = PTMusicQueryKey(
            surface: .library,
            source: normalizedSource,
            category: normalizedSource == .recentlyPlayed ? .songs : category
        )
        begin(key: key, forceRefresh: forceRefresh, debounce: nil)
    }

    public func search(
        term: String,
        category: PTMusicBrowseCategory
    ) {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.count >= 2 else {
            invalidateCurrentRequest()
            currentQueryKey = nil
            payload = nil
            pageState = nil
            state = .idle
            return
        }

        let key = PTMusicQueryKey(
            surface: .search,
            source: .catalog,
            category: category,
            keyword: keyword
        )
        begin(key: key, forceRefresh: false, debounce: 0.3)
    }

    public func retryCurrentQuery() {
        guard let key = currentQueryKey else { return }
        begin(key: key, forceRefresh: true, debounce: nil)
    }

    public func requestAuthorizationAndRetry() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await authorization.requestAuthorization()
            retryCurrentQuery()
        }
    }

    public func loadNextPage() {
        guard
            let key = currentQueryKey,
            key.surface == .library,
            key.source == .library,
            let pageState,
            pageState.hasMore,
            !pageState.isLoadingNextPage,
            requestTask == nil,
            debounceTask == nil
        else {
            return
        }

        let nextGeneration = nextGeneration()
        let nextRequestID = UUID()
        requestID = nextRequestID
        self.pageState = pageState.loadingNextPage()
        startRequest(
            key: key,
            generation: nextGeneration,
            requestID: nextRequestID,
            offset: pageState.offset,
            append: true
        )
    }

    public func invalidate() {
        invalidateCurrentRequest()
        currentQueryKey = nil
        payload = nil
        pageState = nil
        state = .idle
    }

    private func begin(
        key: PTMusicQueryKey,
        forceRefresh _: Bool,
        debounce: TimeInterval?
    ) {
        invalidateCurrentRequest()
        let localGeneration = nextGeneration()
        let localRequestID = UUID()
        currentQueryKey = key
        requestID = localRequestID

        if let cached = cache[key] {
            touchCacheKey(key)
            let isFresh = now().timeIntervalSince(cached.loadedAt) <= cachePolicy.ttl(for: key)
            payload = cached.payload
            pageState = cached.pageState
            state = cached.payload.count == 0
                ? .empty(key)
                : .content(key)
            log(
                isFresh ? "cache_hit" : "cache_stale",
                key: key,
                generation: localGeneration,
                requestID: localRequestID,
                offset: cached.pageState.offset,
                limit: cached.pageState.pageSize,
                resultCount: cached.payload.count,
                cacheHit: isFresh
            )
        } else {
            payload = nil
            pageState = PTMusicPageState(
                pageSize: pageSize(for: key),
                hasMore: true
            )
            state = .loading(key)
            log(
                "cache_miss",
                key: key,
                generation: localGeneration,
                requestID: localRequestID,
                offset: 0,
                limit: pageSize(for: key)
            )
        }

        if let debounce {
            debounceTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                    try Task.checkCancellation()
                } catch {
                    return
                }

                guard let self, self.isCurrent(key, localGeneration, localRequestID) else {
                    return
                }

                self.debounceTask = nil
                self.startRequest(
                    key: key,
                    generation: localGeneration,
                    requestID: localRequestID,
                    offset: 0,
                    append: false
                )
            }
        } else {
            startRequest(
                key: key,
                generation: localGeneration,
                requestID: localRequestID,
                offset: 0,
                append: false
            )
        }
    }

    private func startRequest(
        key: PTMusicQueryKey,
        generation: UInt64,
        requestID: UUID,
        offset: Int,
        append: Bool
    ) {
        let limit = pageSize(for: key)
        log(
            "request_start",
            key: key,
            generation: generation,
            requestID: requestID,
            offset: offset,
            limit: limit
        )
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64((self?.requestTimeout ?? 15) * 1_000_000_000))
            } catch {
                return
            }

            guard let self else { return }
            self.handleTimeout(
                key: key,
                generation: generation,
                requestID: requestID,
                offset: offset
            )
        }

        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = self.now()

            do {
                try await self.preflight(for: key)
                try Task.checkCancellation()

                let result = try await self.fetch(
                    key: key,
                    limit: limit,
                    offset: offset
                )
                try Task.checkCancellation()

                guard self.isCurrent(key, generation, requestID) else {
                    self.log(
                        "stale_dropped",
                        key: key,
                        generation: generation,
                        requestID: requestID,
                        offset: offset,
                        limit: limit,
                        resultCount: result.count,
                        elapsed: self.now().timeIntervalSince(startedAt),
                        staleDropped: true
                    )
                    return
                }

                self.apply(
                    result,
                    key: key,
                    generation: generation,
                    requestID: requestID,
                    offset: offset,
                    limit: limit,
                    append: append,
                    elapsed: self.now().timeIntervalSince(startedAt)
                )
            } catch is CancellationError {
                self.log(
                    "cancelled",
                    key: key,
                    generation: generation,
                    requestID: requestID,
                    offset: offset,
                    limit: limit,
                    cancelled: true
                )
            } catch {
                guard self.isCurrent(key, generation, requestID) else {
                    self.log(
                        "stale_error_dropped",
                        key: key,
                        generation: generation,
                        requestID: requestID,
                        offset: offset,
                        limit: limit,
                        staleDropped: true
                    )
                    return
                }

                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.requestTask = nil
                let mappedError = PTMusicUIError.map(error)
                if append {
                    self.pageState = self.pageState.map {
                        PTMusicPageState(
                            offset: $0.offset,
                            pageSize: $0.pageSize,
                            hasMore: $0.hasMore,
                            isLoadingNextPage: false
                        )
                    }
                }
                self.state = .failed(key, mappedError)
                self.log(
                    "failed",
                    key: key,
                    generation: generation,
                    requestID: requestID,
                    offset: offset,
                    limit: limit,
                    elapsed: self.now().timeIntervalSince(startedAt),
                    error: mappedError
                )
            }
        }
    }

    private func fetch(
        key: PTMusicQueryKey,
        limit: Int,
        offset: Int
    ) async throws -> PTMusicBrowsePayload {
        switch key.surface {
        case .library:
            switch key.source {
            case .recentlyPlayed:
                return .songs(try await libraryService.recentlyPlayedSongs(limit: limit))
            default:
                switch key.category {
                case .songs:
                    return .songs(try await libraryService.songs(limit: limit, offset: offset))
                case .albums:
                    return .albums(try await libraryService.albums(limit: limit, offset: offset))
                case .artists:
                    return .artists(try await libraryService.artists(limit: limit, offset: offset))
                case .playlists:
                    return .playlists(try await libraryService.playlists(limit: limit, offset: offset))
                }
            }
        case .search:
            guard let keyword = key.keyword, !keyword.isEmpty else {
                throw PTMusicUIError.emptyRequest
            }
            switch key.category {
            case .songs:
                return .songs(try await catalogService.searchSongs(term: keyword, limit: limit))
            case .albums:
                return .albums(try await catalogService.searchAlbums(term: keyword, limit: limit))
            case .artists:
                return .artists(try await catalogService.searchArtists(term: keyword, limit: limit))
            case .playlists:
                return .playlists(try await catalogService.searchPlaylists(term: keyword, limit: limit))
            }
        case .collectionDetail:
            throw PTMusicUIError.serviceUnavailable
        }
    }

    private func preflight(for key: PTMusicQueryKey) async throws {
        authorization.refreshAuthorizationStatus()
        switch PTMusicAuthorizationCapability(status: authorization.authorizationStatus) {
        case .notDetermined:
            throw PTMusicUIError.authorizationRequired
        case .denied:
            throw PTMusicUIError.accessDenied
        case .restricted:
            throw PTMusicUIError.accessRestricted
        case .authorized:
            break
        }

        if key.surface == .library {
            await authorization.refreshSubscription()
            guard authorization.hasCloudLibraryEnabled else {
                throw PTMusicUIError.libraryUnavailable
            }
        }
    }

    private func apply(
        _ result: PTMusicBrowsePayload,
        key: PTMusicQueryKey,
        generation: UInt64,
        requestID: UUID,
        offset: Int,
        limit: Int,
        append: Bool,
        elapsed: TimeInterval
    ) {
        timeoutTask?.cancel()
        timeoutTask = nil
        requestTask = nil

        let nextPayload: PTMusicBrowsePayload
        if append, let payload, let combined = payload.appending(result) {
            nextPayload = combined
        } else {
            nextPayload = result
        }

        let hasMore = result.count >= limit
        let nextPageState = PTMusicPageState(
            offset: offset + result.count,
            pageSize: limit,
            hasMore: hasMore,
            isLoadingNextPage: false
        )

        payload = nextPayload
        pageState = nextPageState
        let cacheEntry = CacheEntry(
            payload: nextPayload,
            pageState: nextPageState,
            loadedAt: now()
        )
        cache[key] = cacheEntry
        touchCacheKey(key)
        trimSearchCacheIfNeeded()
        state = nextPayload.count == 0 ? .empty(key) : .content(key)
        let event: String
        if append {
            event = "page_loaded"
        } else if nextPayload.count == 0 {
            event = "empty"
        } else {
            event = "loaded"
        }
        log(
            event,
            key: key,
            generation: generation,
            requestID: requestID,
            offset: offset,
            limit: limit,
            resultCount: result.count,
            elapsed: elapsed
        )
    }

    private func handleTimeout(
        key: PTMusicQueryKey,
        generation: UInt64,
        requestID: UUID,
        offset: Int
    ) {
        guard isCurrent(key, generation, requestID) else { return }

        requestTask?.cancel()
        requestTask = nil
        timeoutTask = nil
        self.generation &+= 1
        pageState = pageState.map {
            PTMusicPageState(
                offset: $0.offset,
                pageSize: $0.pageSize,
                hasMore: $0.hasMore,
                isLoadingNextPage: false
            )
        }
        state = .timedOut(key)
        log(
            "timed_out",
            key: key,
            generation: generation,
            requestID: requestID,
            offset: offset,
            limit: pageState?.pageSize ?? pageSize(for: key),
            timeout: true
        )
    }

    private func invalidateCurrentRequest() {
        requestTask?.cancel()
        debounceTask?.cancel()
        timeoutTask?.cancel()
        requestTask = nil
        debounceTask = nil
        timeoutTask = nil
        requestID = nil
    }

    private func nextGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func touchCacheKey(_ key: PTMusicQueryKey) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    private func trimSearchCacheIfNeeded() {
        let searchKeys = cacheAccessOrder.filter { $0.surface == .search }
        guard searchKeys.count > cachePolicy.searchCacheLimit else { return }

        let keysToRemove = searchKeys.dropLast(cachePolicy.searchCacheLimit)
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            cacheAccessOrder.removeAll { $0 == key }
        }
    }

    private func isCurrent(
        _ key: PTMusicQueryKey,
        _ generation: UInt64,
        _ requestID: UUID
    ) -> Bool {
        currentQueryKey == key && self.generation == generation && self.requestID == requestID
    }

    private func pageSize(for key: PTMusicQueryKey) -> Int {
        switch key.surface {
        case .search:
            return 40
        case .library:
            if key.source == .recentlyPlayed {
                return 40
            }
            return key.category == .songs ? 50 : 40
        case .collectionDetail:
            return 40
        }
    }

    private func log(
        _ event: String,
        key: PTMusicQueryKey,
        generation: UInt64,
        requestID: UUID,
        offset: Int,
        limit: Int,
        resultCount: Int? = nil,
        cacheHit: Bool = false,
        elapsed: TimeInterval? = nil,
        cancelled: Bool = false,
        staleDropped: Bool = false,
        timeout: Bool = false,
        error: PTMusicUIError? = nil
    ) {
        var fields = [
            "event=\(event)",
            "surface=\(key.surface.rawValue)",
            "source=\(key.source.rawValue)",
            "category=\(key.category.rawValue)",
            "keywordLength=\(key.keywordLength)",
            "generation=\(generation)",
            "requestID=\(requestID.uuidString)",
            "offset=\(offset)",
            "limit=\(limit)",
            "cacheHit=\(cacheHit)",
            "cancelled=\(cancelled)",
            "staleDropped=\(staleDropped)",
            "timeout=\(timeout)"
        ]
        if let resultCount { fields.append("resultCount=\(resultCount)") }
        if let elapsed { fields.append("elapsedMs=\(Int(elapsed * 1_000))") }
        if let error { fields.append("errorType=\(error.rawValue)") }
        PTOBDLogger.shared.ptLog("[Music] " + fields.joined(separator: " "))
    }
}
