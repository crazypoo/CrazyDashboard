//
//  PTMusicBrowseStoreTests.swift
//  CrazyDashboardTests
//
//  English: Reliability tests for query identity, cancellation, timeout and access state.
//  Español: Pruebas de fiabilidad para identidad, cancelación, tiempo límite y acceso.
//  中文：覆盖查询身份、取消、超时和授权状态的可靠性测试。
//

import XCTest
import MusicKit
@testable import XP400Ride

@MainActor
final class PTMusicBrowseStoreTests: XCTestCase {

    func testQueryKeySeparatesSurfaceAndSearchKeywordLength() {
        let libraryKey = PTMusicQueryKey(
            surface: .library,
            source: .library,
            category: .songs
        )
        let searchKey = PTMusicQueryKey(
            surface: .search,
            source: .catalog,
            category: .songs,
            keyword: "xp400"
        )

        XCTAssertNotEqual(libraryKey, searchKey)
        XCTAssertEqual(searchKey.keywordLength, 5)
        XCTAssertTrue(searchKey.isSearch)
    }

    func testShortSearchReturnsToIdleWithoutStartingARequest() async {
        let library = PTTestMusicLibraryService()
        let catalog = PTTestMusicCatalogService()
        let auth = PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: true)
        let store = PTMusicBrowseStore(
            libraryService: library,
            catalogService: catalog,
            authorization: auth
        )

        store.search(term: "a", category: .songs)
        await yieldToMainActor()

        XCTAssertEqual(store.state, .idle)
        let callCount = await catalog.searchCallCount
        XCTAssertEqual(callCount, 0)
    }

    func testDeniedAuthorizationIsRepresentedAsUIError() async {
        let auth = PTTestMusicAuthorization(status: .denied, hasCloudLibrary: false)
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(),
            catalogService: PTTestMusicCatalogService(),
            authorization: auth
        )

        store.selectLibrary(source: .library, category: .songs)
        await wait(milliseconds: 40)

        guard case .failed(_, let error) = store.state else {
            return XCTFail("Expected an authorization failure")
        }
        XCTAssertEqual(error, .accessDenied)
    }

    func testAuthorizationMatrixSeparatesUndeterminedRestrictedAndUnavailableLibrary() async {
        let cases: [(MusicAuthorization.Status, Bool, PTMusicUIError)] = [
            (.notDetermined, false, .authorizationRequired),
            (.restricted, false, .accessRestricted),
            (.authorized, false, .libraryUnavailable)
        ]

        for (status, hasCloudLibrary, expectedError) in cases {
            let store = PTMusicBrowseStore(
                libraryService: PTTestMusicLibraryService(),
                catalogService: PTTestMusicCatalogService(),
                authorization: PTTestMusicAuthorization(
                    status: status,
                    hasCloudLibrary: hasCloudLibrary
                )
            )

            store.selectLibrary(source: .library, category: .songs)
            await wait(milliseconds: 40)

            guard case .failed(_, let error) = store.state else {
                return XCTFail("Expected an authorization or library failure for \(status)")
            }
            XCTAssertEqual(error, expectedError)
        }
    }

    func testRapidLibrarySegmentSwitchKeepsTheLatestCategory() async {
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(delayNanoseconds: 80_000_000),
            catalogService: PTTestMusicCatalogService(),
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: true)
        )

        store.selectLibrary(source: .library, category: .songs)
        store.selectLibrary(source: .library, category: .albums)
        store.selectLibrary(source: .library, category: .artists)
        store.selectLibrary(source: .library, category: .playlists)
        await wait(milliseconds: 180)

        XCTAssertEqual(store.currentQueryKey?.category, .playlists)
        XCTAssertEqual(store.state.queryKey?.category, .playlists)
    }

    func testSearchReplacesDefaultLibraryRequest() async {
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(delayNanoseconds: 100_000_000),
            catalogService: PTTestMusicCatalogService(delayNanoseconds: 20_000_000),
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: true)
        )

        store.selectLibrary(source: .library, category: .songs)
        store.search(term: "abc", category: .songs)
        await wait(milliseconds: 450)

        XCTAssertEqual(store.currentQueryKey?.surface, .search)
        XCTAssertEqual(store.currentQueryKey?.keyword, "abc")
        XCTAssertEqual(store.state.queryKey?.keyword, "abc")
    }

    func testRecentlyPlayedUsesIndependentSourceAndPageSize() {
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(),
            catalogService: PTTestMusicCatalogService(),
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: true)
        )

        store.selectLibrary(source: .recentlyPlayed, category: .songs)

        XCTAssertEqual(store.currentQueryKey?.source, .recentlyPlayed)
        XCTAssertEqual(store.currentQueryKey?.category, .songs)
        XCTAssertEqual(store.pageState?.pageSize, 40)
    }

    func testLatestSearchGenerationWinsWhenResponsesArriveOutOfOrder() async {
        let catalog = PTTestMusicCatalogService(delayNanoseconds: 80_000_000)
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(),
            catalogService: catalog,
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: false)
        )

        store.search(term: "first", category: .songs)
        store.search(term: "second", category: .songs)
        await wait(milliseconds: 150)

        XCTAssertEqual(store.currentQueryKey?.keyword, "second")
        XCTAssertEqual(store.state.queryKey?.keyword, "second")
    }

    func testTimeoutInvalidatesLateResponse() async {
        let catalog = PTTestMusicCatalogService(delayNanoseconds: 180_000_000)
        let key = PTMusicQueryKey(
            surface: .search,
            source: .catalog,
            category: .songs,
            keyword: "timeout"
        )
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(),
            catalogService: catalog,
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: false),
            requestTimeout: 0.05
        )

        store.search(term: key.keyword ?? "", category: .songs)
        await wait(milliseconds: 100)
        XCTAssertEqual(store.state.queryKey, key)
        if case .timedOut = store.state {
            // Expected: the late service response must not restore content.
        } else {
            XCTFail("Expected a timeout state")
        }

        await wait(milliseconds: 180)
        if case .timedOut = store.state {
            // Expected: the cancelled late response remains ignored.
        } else {
            XCTFail("Late response changed the timeout state")
        }
    }

    func testLibraryPageStateUsesCategorySpecificPageSizes() async {
        let store = PTMusicBrowseStore(
            libraryService: PTTestMusicLibraryService(),
            catalogService: PTTestMusicCatalogService(),
            authorization: PTTestMusicAuthorization(status: .authorized, hasCloudLibrary: true)
        )

        store.selectLibrary(source: .library, category: .songs)
        XCTAssertEqual(store.pageState?.pageSize, 50)

        store.selectLibrary(source: .library, category: .albums)
        XCTAssertEqual(store.pageState?.pageSize, 40)
        await wait(milliseconds: 40)
        XCTAssertFalse(store.pageState?.isLoadingNextPage ?? true)
        store.loadNextPage()
        XCTAssertFalse(store.pageState?.isLoadingNextPage ?? true)
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func yieldToMainActor() async {
        await wait(milliseconds: 10)
    }
}

@MainActor
private final class PTTestMusicAuthorization: PTMusicAuthorizationProviding {
    let authorizationStatus: MusicAuthorization.Status
    let hasCloudLibraryEnabled: Bool
    let subscription: MusicSubscription? = nil

    init(status: MusicAuthorization.Status, hasCloudLibrary: Bool) {
        authorizationStatus = status
        hasCloudLibraryEnabled = hasCloudLibrary
    }

    func refreshAuthorizationStatus() {}
    func requestAuthorization() async -> MusicAuthorization.Status {
        authorizationStatus
    }
    func refreshSubscription() async {}
}

private actor PTTestMusicLibraryService: PTMusicLibraryServing {
    private let delayNanoseconds: UInt64
    private let failure: PTMusicUIError?

    init(delayNanoseconds: UInt64 = 0, failure: PTMusicUIError? = nil) {
        self.delayNanoseconds = delayNanoseconds
        self.failure = failure
    }

    func songs(limit: Int, offset: Int) async throws -> [Song] {
        try await response()
    }

    func albums(limit: Int, offset: Int) async throws -> [Album] {
        try await response()
    }

    func artists(limit: Int, offset: Int) async throws -> [Artist] {
        try await response()
    }

    func playlists(limit: Int, offset: Int) async throws -> [Playlist] {
        try await response()
    }

    func recentlyPlayedSongs(limit: Int) async throws -> [Song] {
        try await response()
    }

    private func response<T>() async throws -> [T] {
        if delayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                // English: Ignore cancellation to model a late system response.
                // Español: Ignoramos la cancelación para modelar una respuesta tardía.
                // 中文：故意忽略取消，用来模拟系统晚到的响应。
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        if let failure { throw failure }
        return []
    }
}

private actor PTTestMusicCatalogService: PTMusicCatalogServing {
    private let delayNanoseconds: UInt64
    private(set) var searchCallCount = 0

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func searchSongs(term: String, limit: Int) async throws -> [Song] {
        searchCallCount += 1
        return try await response()
    }

    func searchAlbums(term: String, limit: Int) async throws -> [Album] {
        try await response()
    }

    func searchArtists(term: String, limit: Int) async throws -> [Artist] {
        try await response()
    }

    func searchPlaylists(term: String, limit: Int) async throws -> [Playlist] {
        try await response()
    }

    private func response<T>() async throws -> [T] {
        if delayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        return []
    }
}
