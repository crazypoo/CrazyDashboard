//
//  PTDashboardThemeEngine.swift
//  CrazyDashboard
//
//  EN: Main-actor theme coordinator with bounded artwork-token caching.
//  ES: Coordinador de temas en el actor principal con caché acotada de tokens.
//  中文：主线程主题协调器与有界封面令牌缓存。
//

import Foundation
import UIKit

@MainActor
public final class PTDashboardThemeCache {
    private final class Box: NSObject {
        let palette: PTArtworkColorPalette

        init(palette: PTArtworkColorPalette) {
            self.palette = palette
        }
    }

    private let cache = NSCache<NSString, Box>()

    public init() {
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024
    }

    public func palette(for key: String) -> PTArtworkColorPalette? {
        cache.object(forKey: key as NSString)?.palette
    }

    public func insert(_ palette: PTArtworkColorPalette, for key: String) {
        cache.setObject(Box(palette: palette), forKey: key as NSString)
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}

@MainActor
public final class PTDashboardThemeEngine {
    public static let shared = PTDashboardThemeEngine()
    public static let didChange = Notification.Name("PTDashboardThemeEngine.didChange")

    public private(set) var tokens: PTDashboardThemeTokens = .fallback
    public var onChange: ((PTDashboardThemeTokens) -> Void)?

    private let cache = PTDashboardThemeCache()
    private var currentPalette: PTArtworkColorPalette?
    private var currentContext: PTDashboardContext = .parked
    private var currentArtworkKey = ""
    private var lastArtworkData: Data?
    private var extractionTask: Task<Void, Never>?
    private var contextObserver: NSObjectProtocol?
    private var clientCount = 0

    private init() {}

    // EN: Dashboard and Twin pages share one observer so theme changes never duplicate work.
    // ES: El tablero y Twin comparten un observador para no duplicar trabajo al cambiar el tema.
    // 中文：Dashboard 与 Twin 页面共享一个观察者，避免主题变化时重复计算。
    public func start() {
        clientCount += 1
        guard clientCount == 1 else {
            update(context: PTDashboardContextEngine.shared.snapshot.primaryContext)
            return
        }

        contextObserver = NotificationCenter.default.addObserver(
            forName: PTDashboardContextEngine.didChange,
            object: PTDashboardContextEngine.shared,
            queue: .main
        ) { [weak self] notification in
            guard let snapshot = notification.userInfo?["snapshot"] as? PTDashboardContextSnapshot else { return }
            Task { @MainActor [weak self] in
                self?.update(context: snapshot.primaryContext)
            }
        }
        update(context: PTDashboardContextEngine.shared.snapshot.primaryContext)
    }

    public func stop() {
        guard clientCount > 0 else { return }
        clientCount -= 1
        guard clientCount == 0 else { return }
        if let contextObserver {
            NotificationCenter.default.removeObserver(contextObserver)
            self.contextObserver = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        PTMotoUserDefaultStruct.PTDashboardArtworkThemeEnabled = enabled
        extractionTask?.cancel()
        extractionTask = nil
        guard enabled else {
            currentPalette = nil
            publish()
            return
        }

        guard let lastArtworkData, !currentArtworkKey.isEmpty else {
            currentPalette = nil
            publish()
            return
        }
        beginExtraction(data: lastArtworkData, key: currentArtworkKey)
    }

    // EN: A missing or permission-limited artwork is a normal fallback, not an error state.
    // ES: Una portada ausente o limitada por permisos es un fallback normal, no un error.
    // 中文：封面缺失或权限受限属于正常回退，不当作错误状态。
    public func updateArtwork(_ image: UIImage?, trackIdentifier: String) {
        extractionTask?.cancel()
        extractionTask = nil
        let imageData = image?.pngData()
        let artworkKey = imageData.map {
            "\(trackIdentifier)|\($0.count)|\($0.hashValue)"
        } ?? trackIdentifier
        currentArtworkKey = artworkKey
        lastArtworkData = imageData

        guard PTMotoUserDefaultStruct.PTDashboardArtworkThemeEnabled,
              let data = lastArtworkData,
              !trackIdentifier.isEmpty else {
            currentPalette = nil
            publish()
            return
        }

        if let cached = cache.palette(for: artworkKey) {
            currentPalette = cached
            publish()
            return
        }
        beginExtraction(data: data, key: artworkKey)
    }

    public func update(context: PTDashboardContext) {
        guard currentContext != context else { return }
        currentContext = context
        publish()
    }

    private func beginExtraction(data: Data, key: String) {
        let extractionKey = key
        extractionTask = Task { @MainActor [weak self] in
            let palette = await Task.detached(priority: .utility) {
                PTDashboardArtworkColorExtractor.extract(from: data)
            }.value

            guard let self,
                  !Task.isCancelled,
                  self.currentArtworkKey == extractionKey else {
                return
            }
            self.extractionTask = nil
            if let palette {
                self.cache.insert(palette, for: extractionKey)
            }
            self.currentPalette = palette
            self.publish()
        }
    }

    private func publish() {
        let next = PTDashboardThemeResolver.resolve(
            palette: currentPalette,
            enabled: PTMotoUserDefaultStruct.PTDashboardArtworkThemeEnabled,
            context: currentContext
        )
        guard next != tokens else { return }
        tokens = next
        onChange?(next)
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: ["tokens": next]
        )
    }

    deinit {
        extractionTask?.cancel()
        if let contextObserver {
            NotificationCenter.default.removeObserver(contextObserver)
        }
    }
}
