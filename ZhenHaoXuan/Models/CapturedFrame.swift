import Foundation
import UIKit

/// 帧来源类型
enum FrameSource: Codable, Equatable {
    case video(url: URL)
    case livePhoto(assetID: String)

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type, videoURL, assetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "video":
            let url = try container.decode(URL.self, forKey: .videoURL)
            self = .video(url: url)
        case "livePhoto":
            let assetID = try container.decode(String.self, forKey: .assetID)
            self = .livePhoto(assetID: assetID)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown FrameSource type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .video(let url):
            try container.encode("video", forKey: .type)
            try container.encode(url, forKey: .videoURL)
        case .livePhoto(let assetID):
            try container.encode("livePhoto", forKey: .type)
            try container.encode(assetID, forKey: .assetID)
        }
    }
}

/// 一张已捕获的画面帧。
/// 原图保存在磁盘（避免大量大图占用内存导致闪退），内存中只保留缩略图用于展示。
struct CapturedFrame: Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let videoName: String
    let captureDate: Date
    /// 原图在磁盘上的文件名，导出时按需读取
    let imageFileName: String
    /// 用于列表展示的缩略图
    let thumbnail: UIImage
    /// 帧的来源（视频帧 或 Live Photo 关键帧）
    let source: FrameSource

    /// 从磁盘读取原始大图（用于导出到相册）
    func loadFullImage() -> UIImage? {
        FrameStore.shared.fullImage(fileName: imageFileName)
    }

    /// 导出时的文件名，格式：视频名_时间点（如：生日party_01m23s.jpg）
    func exportFileName(extension: String) -> String {
        let name = (videoName as NSString).deletingPathExtension
        let totalSeconds = Int(timestamp.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let timeStr = String(format: "%02dm%02ds", minutes, seconds)
        return "\(name)_\(timeStr).\(`extension`)"
    }
}
