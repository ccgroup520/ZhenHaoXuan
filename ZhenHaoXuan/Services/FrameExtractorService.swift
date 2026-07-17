import Foundation
import AVFoundation
import UIKit
import ImageIO

/// 视频帧提取服务。
///
/// 通俗解释：这是从视频里"截图"的工具。
/// 你告诉它"我要第 3.5 秒的画面"，它就把那一帧的图片交给你。
///
/// 优化：
/// - 统一用 async/await，不再混用回调、GCD、Task 三种方式
/// - 同一个视频 URL 的 AVAssetImageGenerator 会缓存复用（不重复"买相机"）
actor FrameExtractorService {
    static let shared = FrameExtractorService()

    /// 缓存：按视频 URL 存储 AVAssetImageGenerator，避免重复创建
    private var generatorCache: [URL: AVAssetImageGenerator] = [:]

    private init() {}

    /// 从视频指定时间点提取一帧图片
    func extractFrame(from videoURL: URL, at time: TimeInterval) async throws -> UIImage {
        let asset = AVURLAsset(url: videoURL)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        // HDR 增强（仅付费会员）：以 2x 超采样提取，保留更多画面细节
        let useHDR = await MainActor.run {
            ExportSettings.shared.hdrEnabled && VIPManager.shared.canUseHDR
        }

        let generator: AVAssetImageGenerator
        if useHDR {
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceAfter = .zero
            generator.requestedTimeToleranceBefore = .zero
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try? await track.load(.naturalSize)
                if let size = naturalSize {
                    generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
                }
            }
        } else {
            generator = cachedGenerator(for: videoURL)
        }

        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
        } catch {
            throw FrameExtractorError.extractionFailed(underlying: error)
        }

        return UIImage(cgImage: cgImage)
    }

    /// 带动画帧元数据的提取（保留 EXIF 等信息）
    func extractFrameWithMetadata(from videoURL: URL, at time: TimeInterval) async throws -> (UIImage, [String: Any]?) {
        let asset = AVURLAsset(url: videoURL)
        let metadata = try? await asset.load(.metadata)
        let metadataDict = await withTaskGroup(of: (String, Any)?.self) { group -> [String: Any] in
            guard let metadata = metadata else { return [:] }
            for item in metadata {
                group.addTask {
                    guard let key = item.commonKey?.rawValue else { return nil }
                    let value = try? await item.load(.value)
                    return value.map { (key, $0) }
                }
            }
            var dict = [String: Any]()
            for await pair in group {
                if let (key, value) = pair {
                    dict[key] = value
                }
            }
            return dict
        }

        let image = try await extractFrame(from: videoURL, at: time)
        return (image, metadataDict)
    }

    /// 清除指定视频的 generator 缓存（视频关闭时调用）
    func clearCache(for videoURL: URL) {
        generatorCache.removeValue(forKey: videoURL)
    }

    /// 清除所有缓存
    func clearAllCache() {
        generatorCache.removeAll()
    }

    // MARK: - Private

    /// 获取或创建 AVAssetImageGenerator（带缓存）
    private func cachedGenerator(for videoURL: URL) -> AVAssetImageGenerator {
        if let existing = generatorCache[videoURL] {
            return existing
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        generatorCache[videoURL] = generator
        return generator
    }
}

enum FrameExtractorError: LocalizedError {
    case extractionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let error):
            return "帧提取失败: \(error.localizedDescription)"
        }
    }
}
