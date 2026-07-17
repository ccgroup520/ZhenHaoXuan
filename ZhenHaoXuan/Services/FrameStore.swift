import Foundation
import UIKit

/// 帧存储：把抓取的原图持久化到磁盘，内存中只保留小缩略图。
///
/// 通俗解释：这是一个"照片档案室"。
/// - 原图（无损PNG）放在 Application Support/CapturedFrames 的档案柜里
/// - 缩略图（小尺寸JPEG）用于列表快速浏览
/// - index.json 是"目录索引"，记录每张帧的信息
///
/// 安全机制：
/// - actor 保证同时只有一个人能改档案室（自动排队，不打架）
/// - 最多存 maxFrameCount 张图
/// - 总量不超过 maxTotalSize 字节
/// - 超出限制时自动删最旧的（先来先走）
///
/// 为什么不用 class + NSLock？
/// NSLock 就像一把手动锁——忘了开锁别人就永远进不去（死锁）。
/// actor 是 Swift 内置的"自动锁"，编译器帮你检查，不会忘。
actor FrameStore {
    static let shared = FrameStore()

    /// 最多保留的帧数量
    static let maxFrameCount = 100
    /// 最多占用的磁盘空间（字节），约 500MB
    static let maxTotalSize: Int64 = 500_000_000

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let indexURL: URL
    private let thumbnailMaxPixel: CGFloat = 600

    /// 磁盘上的帧元数据记录
    private struct FrameRecord: Codable {
        let id: UUID
        let timestamp: TimeInterval
        let videoName: String
        let captureDate: Date
        let imageFileName: String
        let thumbnailFileName: String
        let source: FrameSource
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

    /// 读取所有已保存的帧（只加载小缩略图，不占内存）
    /// 按捕获时间倒序排列（最新捕获的在最前面）
    func loadAll() -> [CapturedFrame] {
        let records = readIndex()
        return records
            .sorted { $0.captureDate > $1.captureDate }
            .compactMap { record in
            let thumbURL = directoryURL.appendingPathComponent(record.thumbnailFileName)
            guard let thumbnail = UIImage(contentsOfFile: thumbURL.path) else { return nil }
            return CapturedFrame(
                id: record.id,
                timestamp: record.timestamp,
                videoName: record.videoName,
                captureDate: record.captureDate,
                imageFileName: record.imageFileName,
                thumbnail: thumbnail,
                source: record.source
            )
        }
    }

    /// 新增一张帧：写盘 → 更新索引 → 返回模型对象。
    func add(image: UIImage, timestamp: TimeInterval, videoName: String, source: FrameSource = .video(url: URL(fileURLWithPath: ""))) -> CapturedFrame? {
        // 写入前先确保容量不超标
        enforceStorageLimits()

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
            thumbnailFileName: thumbnailFileName,
            source: source
        )

        var records = readIndex()
        records.append(record)
        writeIndex(records)

        return CapturedFrame(
            id: id,
            timestamp: timestamp,
            videoName: videoName,
            captureDate: captureDate,
            imageFileName: imageFileName,
            thumbnail: thumbnail,
            source: source
        )
    }

    /// 删除指定的一批帧
    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        var records = readIndex()
        for record in records where ids.contains(record.id) {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.imageFileName))
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.thumbnailFileName))
        }
        records.removeAll { ids.contains($0.id) }
        writeIndex(records)
    }

    /// 清空所有帧
    func removeAll() {
        let records = readIndex()
        for record in records {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.imageFileName))
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.thumbnailFileName))
        }
        writeIndex([])
    }

    /// 按需从磁盘读取原始大图（导出时使用）
    nonisolated func fullImage(fileName: String) -> UIImage? {
        let path = FrameStore.directoryURL().appendingPathComponent(fileName).path
        return UIImage(contentsOfFile: path)
    }

    /// 获取总占用空间（字节）
    func totalSize() -> Int64 {
        let records = readIndex()
        var total: Int64 = 0
        for record in records {
            let imageURL = directoryURL.appendingPathComponent(record.imageFileName)
            let thumbURL = directoryURL.appendingPathComponent(record.thumbnailFileName)
            if let imageAttrs = try? fileManager.attributesOfItem(atPath: imageURL.path),
               let size = imageAttrs[.size] as? Int64 {
                total += size
            }
            if let thumbAttrs = try? fileManager.attributesOfItem(atPath: thumbURL.path),
               let size = thumbAttrs[.size] as? Int64 {
                total += size
            }
        }
        return total
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

    /// 生成用于列表展示的缩略图，最长边不超过 thumbnailMaxPixel
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

    // MARK: - 容量管理

    /// 确保存储不超过数量和容量限制。超出时从旧到新删除。
    private func enforceStorageLimits() {
        var records = readIndex()
        guard !records.isEmpty else { return }

        // 先按数量限制清理
        while records.count >= Self.maxFrameCount {
            if let oldest = records.first {
                removeFiles(for: oldest)
                records.removeFirst()
            }
        }

        // 再按容量限制清理
        while totalSize() > Self.maxTotalSize, let oldest = records.first {
            removeFiles(for: oldest)
            records.removeFirst()
        }

        if records.count < readIndex().count {
            writeIndex(records)
        }
    }

    private func removeFiles(for record: FrameRecord) {
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.imageFileName))
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(record.thumbnailFileName))
    }

    /// nonisolated 辅助：获取目录 URL（供 nonisolated fullImage 使用）
    private static func directoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CapturedFrames", isDirectory: true)
    }
}
