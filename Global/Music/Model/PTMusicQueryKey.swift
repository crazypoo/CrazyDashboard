//
//  PTMusicQueryKey.swift
//  CrazyDashboard
//
//  English: A stable identity for every music request.
//  Español: Una identidad estable para cada solicitud de música.
//  中文：为每一次音乐请求提供稳定、可比较的身份。
//

import Foundation

public enum PTMusicQuerySurface: String, Hashable, Sendable {
    case library
    case search
    case collectionDetail
}

public struct PTMusicQueryKey: Hashable, Sendable {
    public let surface: PTMusicQuerySurface
    public let source: PTMusicSource
    public let category: PTMusicBrowseCategory
    public let keyword: String?

    public init(
        surface: PTMusicQuerySurface,
        source: PTMusicSource,
        category: PTMusicBrowseCategory,
        keyword: String? = nil
    ) {
        self.surface = surface
        self.source = source
        self.category = category
        self.keyword = keyword
    }

    public var keywordLength: Int {
        keyword?.count ?? 0
    }

    public var isSearch: Bool {
        surface == .search
    }
}
