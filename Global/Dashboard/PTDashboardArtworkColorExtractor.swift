//
//  PTDashboardArtworkColorExtractor.swift
//  CrazyDashboard
//
//  EN: Small native image sampler used by the dashboard theme engine.
//  ES: Muestreador nativo de imágenes usado por el motor de temas del tablero.
//  中文：仪表盘主题引擎使用的轻量原生图片采样器。
//

import CoreGraphics
import Foundation
import ImageIO

// EN: The extractor receives PNG data so no UIKit object crosses the background boundary.
// ES: El extractor recibe datos PNG para que ningún objeto UIKit cruce el límite de fondo.
// 中文：提取器只接收 PNG 数据，避免 UIKit 对象跨越后台并发边界。
public nonisolated enum PTDashboardArtworkColorExtractor {

    public static func extract(from data: Data) -> PTArtworkColorPalette? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 24
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var totalWeight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var accentScore = -Double.infinity
        var accent = (red: 0.15, green: 0.45, blue: 0.95)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.25 else { continue }

            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let brightness = (maximum + minimum) * 0.5
            guard brightness > 0.015 else { continue }

            let saturation = maximum - minimum
            let weight = alpha * (0.45 + saturation * 1.8)
            totalWeight += weight
            red += r * weight
            green += g * weight
            blue += b * weight

            let vividScore = saturation * alpha * (0.35 + brightness)
            if vividScore > accentScore {
                accentScore = vividScore
                accent = (r, g, b)
            }
        }

        guard totalWeight > 0 else { return nil }
        return PTArtworkColorPalette(
            dominant: PTDashboardThemeColor(
                red: red / totalWeight,
                green: green / totalWeight,
                blue: blue / totalWeight
            ),
            accent: PTDashboardThemeColor(
                red: accent.red,
                green: accent.green,
                blue: accent.blue
            )
        )
    }
}

