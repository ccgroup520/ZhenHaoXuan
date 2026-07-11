import Foundation

/// 临时媒体文件管理：所选视频/Live Photo 视频会被复制到一个专用临时目录。
/// 统一在此目录管理，便于按需删除与 App 启动时清理残留，避免临时文件越积越多占满存储。
enum MediaTempStore {
    /// 专用临时目录，独立子目录方便整体清理，避免误删系统其他临时文件。
    static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 为来源文件生成一个唯一的临时存放路径。
    static func makeDestinationURL(for sourceURL: URL) -> URL {
        directory.appendingPathComponent(UUID().uuidString + "-" + sourceURL.lastPathComponent)
    }

    /// 删除指定的临时文件（例如退出视频预览时）。
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 清空目录内所有临时文件（App 启动时调用，清理上次运行的残留）。
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
