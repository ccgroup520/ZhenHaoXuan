import Foundation
import UIKit

/// 帧存储：把抓取的原图持久化到磁盘，内存中只保留小缩略图，避免大量大图占满内存导致闪退。
/// - 原图：无损 PNG，保存在 Application Support/CapturedFrames 下，导出时按需读取。
/// - 缩略图：小尺寸 JPEG，供列表展示与 App 重启后快速恢复。
/// - 元数据：index.json 记录每张帧的信息，保证退出 App 后不丢失。
final class FrameStore {
    static let shared = FrameStore()

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let indexURL: URL
    private let thumbnailMaxPixel: CGFloat = 600
    /// 保护 index.json 的读改写，避免并发损坏。
    private let lock = NSLock()

    /// 磁盘上的帧元数据记录。
    private struct FrameRecord: Codable {
        let id: UUID
        let timestamp: TimeInterval
        let videoName: String
        let captureDate: Date
        let imageFileName: String
        let thumbnailFileName: String
    }

    private init() {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        directoryURL = base.appendingPathComponent("CapturedFrames", isDirectory: true)
        indexURL = directoryURL.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// 读取所有已保存的帧（App 启动/进入画廊时用），只加载小缩略图。
    func loadAll() -> [CapturedFrame] {
        lock.lock()
        let records = readIndex()
        lock.unlock()

        return records.compactMap { record in
            let thumbURL = directoryURL.appendingPathComponent(record.thumbnailFileName)
            guard let thumbnail = UIImage(contentsOfFile: thumbURL.path) else { return nil }
            return CapturedFrame(
                id: record.id,
                timestamp: record.timestamp,
                videoName: record.videoName,
                captureDate: record.captureDate,
                imageFileName: record.imageFileName,
                thumbnail: thumbnail
            )
        }
    }

    /// 新增一张帧：把原图与缩略图写入磁盘，并更新索引。返回可用于展示的 CapturedFrame。
    /// 注意：涉及磁盘写入，建议在后台线程调用。
    func add(image: UIImage, timestamp: TimeInterval, videoName: String) -> CapturedFrame? {
        let id = UUID()
        let imageFileName = "\(id.uuidString).png"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
        let imageURL = directoryURL.appendingPathComponent(imageFileName)
        let thumbURL = directoryURL.appendingPathComponent(thumbnailFileName)

        guard let fullData = image.pngData() else { return nil }
        let thumbnail = makeThumbnail(from: image)
        guard let thumbData = thumbnail.jpegData(compressionQuality: 0.85) else { return nil }

        do {
            try fullData.write(to: imageURL, options: .atomic)
            try thumbData.write(to: thumbURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbURL)
            return nil
        }

        let captureDate = Date()
        let record = FrameRecord(
            id: id,
            timestamp: timestamp,
            videoName: videoName,
            captureDate: captureDate,
            imageFileName: imageFileName,
            thumbnailFileName: thumbnailFileName
        )

        lock.lock()
        var records = readIndex()
        records.append(record)
        writeIndex(records)
        lock.unlock()

        return CapturedFrame(
            id: id,
            timestamp: timestamp,
            videoName: videoName,
            captureDate: captureDate,
            imageFileName: imageFileName,
            thumbnail: thumbnail
        )
    }

    /// 删除指定的一批帧（磁盘文件 + 索引）。
    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var records = readIndex()
        for record in records where ids.contains(record.id) {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.imageFileName))
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.thumbnailFileName))
        }
        records.removeAll { ids.contains($0.id) }
        writeIndex(records)
    }

    /// 清空所有帧。
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        let records = readIndex()
        for record in records {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.imageFileName))
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.thumbnailFileName))
        }
        writeIndex([])
    }

    /// 按需从磁盘读取原始大图（导出时使用）。
    func fullImage(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: directoryURL.appendingPathComponent(fileName).path)
    }

    // MARK: - Private

    private func readIndex() -> [FrameRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([FrameRecord].self, from: data)) ?? []
    }

    private func writeIndex(_ records: [FrameRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// 生成用于列表展示的缩略图，最长边不超过 thumbnailMaxPixel。
    private func makeThumbnail(from image: UIImage) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > thumbnailMaxPixel, longestSide > 0 else { return image }

        let scale = thumbnailMaxPixel / longestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
