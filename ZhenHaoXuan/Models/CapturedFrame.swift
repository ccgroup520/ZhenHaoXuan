import Foundation
import UIKit

/// 一张已捕获的画面帧。
/// 原图保存在磁盘（避免大量大图占用内存导致闪退），内存中只保留缩略图用于展示。
struct CapturedFrame: Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let videoName: String
    let captureDate: Date
    /// 原图在磁盘上的文件名，导出时按需读取。
    let imageFileName: String
    /// 用于列表展示的缩略图。
    let thumbnail: UIImage

    /// 从磁盘读取原始大图（用于导出到相册）。
    func loadFullImage() -> UIImage? {
        FrameStore.shared.fullImage(fileName: imageFileName)
    }
}
