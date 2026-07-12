import Foundation

/// 临时媒体文件管理：所选视频/Live Photo 视频会被复制到一个专用临时目录。
///
/// 优化：每次选择新文件时自动清理旧临时文件，不再等到 App 重启才清。
enum MediaTempStore {
    /// 专用临时目录
    static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 为来源文件生成一个唯一的临时存放路径
    static func makeDestinationURL(for sourceURL: URL) -> URL {
        directory.appendingPathComponent(UUID().uuidString + "-" + sourceURL.lastPathComponent)
    }

    /// 在选择新文件之前，先清理旧临时文件
    static func prepareForNewSelection() {
        removeAll()
    }

    /// 删除指定的临时文件
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 清空目录内所有临时文件
    static func removeAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
