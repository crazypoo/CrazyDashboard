//
//  PTMusicArtworkCache.swift
//  CrazyDashboard
//

import Foundation
import UIKit
import MusicKit

@MainActor
public final class PTMusicArtworkCache {

    public static let shared = PTMusicArtworkCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    public func image(
        for artwork: Artwork?,
        targetSize: CGSize
    ) async -> UIImage? {
        guard
            let artwork,
            targetSize.width > 0,
            targetSize.height > 0,
            let url = artwork.url(
                width: max(1, Int(targetSize.width.rounded(.up))),
                height: max(1, Int(targetSize.height.rounded(.up)))
            )
        else {
            return nil
        }

        return await image(from: url)
    }

    public func image(from url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let data = await loadData(from: url), !Task.isCancelled else {
            return nil
        }

        guard let image = UIImage(data: data) else {
            return nil
        }

        cache.setObject(
            image,
            forKey: key,
            cost: data.count
        )

        return image
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    private func loadData(from url: URL) async -> Data? {
        let scheme = url.scheme?.lowercased()

        if scheme == "http" || scheme == "https" {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    return nil
                }

                return data
            } catch {
                return nil
            }
        }

        /*
         MusicKit artwork URLs can use a custom URL scheme on some OS versions.
         Data(contentsOf:) is synchronous, so it must not run on MainActor.

         Safety invariant:
         - the detached task captures only immutable Foundation.URL;
         - it returns Foundation.Data (Sendable);
         - no UIKit object or shared mutable state crosses this boundary.
         */
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
    }
}
