//
//  PTFeedbackAttachmentBuilder.swift
//  CrazyDashboard
//
//  Re-rendering strips EXIF/GPS metadata before encryption.
//

import Foundation
import UIKit

@MainActor
public enum PTFeedbackAttachmentBuilder {
    public static let maximumScreenshotBytes = 2 * 1024 * 1024
    public static let maximumDimension: CGFloat = 2048

    public static func sanitizedJPEG(
        from image: UIImage,
        quality: CGFloat = 0.82
    ) throws -> PTFeedbackAttachmentDraft {
        let size = scaledSize(for: image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: quality),
              data.count <= maximumScreenshotBytes else {
            throw PTFeedbackError.payloadTooLarge(
                rendered.jpegData(compressionQuality: 0.65)?.count ?? 0
            )
        }
        return .init(
            kind: .screenshot,
            mimeType: "image/jpeg",
            data: data
        )
    }

    public static func diagnosticsJSON(
        _ snapshot: PTFeedbackDiagnosticsSnapshot
    ) throws -> PTFeedbackAttachmentDraft {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "summary": snapshot.values
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        guard data.count <= 512 * 1024 else {
            throw PTFeedbackError.payloadTooLarge(data.count)
        }
        return .init(
            kind: .diagnostics,
            mimeType: "application/json",
            data: data
        )
    }

    private static func scaledSize(for size: CGSize) -> CGSize {
        guard max(size.width, size.height) > maximumDimension else { return size }
        let scale = maximumDimension / max(size.width, size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }
}
