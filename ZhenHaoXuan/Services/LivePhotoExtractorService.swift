import Foundation
import Photos
import UIKit

/// Live Photo 静态关键帧提取服务。
///
/// 通俗解释：Live Photo 是一段 3 秒小视频 + 一张高清静态照片的"组合包"。
/// 这个服务就是从这个组合包里把那张高清静态照片取出来。
///
/// 实现原理：
/// PHImageManager.requestImage 指定 targetSize = PHImageManagerMaximumSize
/// 就能拿到 Live Photo 中分辨率最高的静态关键帧。
actor LivePhotoExtractorService {
    static let shared = LivePhotoExtractorService()

    private init() {}

    /// 从 Live Photo 的 PHAsset 中提取高分辨率静态关键帧
    func extractKeyImage(from asset: PHAsset) async throws -> UIImage {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true  // iCloud 照片也能取
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // 检查是否被取消
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: LivePhotoError.cancelled)
                    return
                }

                // 检查错误
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                // 检查是否是低质量缩略图（第一次回调可能返回缩略图）
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                    // 跳过缩略图回调，等待高质量版本
                    return
                }

                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: LivePhotoError.extractionFailed)
                }
            }
        }
    }
}

enum LivePhotoError: LocalizedError {
    case extractionFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .extractionFailed:
            return "无法从 Live Photo 中提取图片，请重试。"
        case .cancelled:
            return "操作已取消。"
        }
    }
}
