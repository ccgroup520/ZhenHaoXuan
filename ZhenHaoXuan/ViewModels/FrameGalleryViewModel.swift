import Foundation
import Combine
import UIKit

@MainActor
final class FrameGalleryViewModel: ObservableObject {
    @Published var isExporting = false
    @Published var exportSuccess = false
    @Published var errorMessage: String?

    private let imageExportService = ImageExportService.shared

    func exportFrames(_ frames: [CapturedFrame], completion: @escaping (Bool) -> Void) {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil

        Task {
            // 导出时才按需从磁盘读取原图，避免一直占用内存
            let exportItems: [(image: UIImage, filename: String)] = frames.compactMap { frame in
                guard let image = frame.loadFullImage() else { return nil }
                let ext = ExportSettings.shared.format.fileExtension
                let filename = frame.exportFileName(extension: ext)
                return (image, filename)
            }

            guard exportItems.count == frames.count, !exportItems.isEmpty else {
                self.isExporting = false
                self.errorMessage = "图片读取失败，请重试。"
                completion(false)
                return
            }

            do {
                let count = try await imageExportService.exportMultipleToPhotoLibrary(images: exportItems)
                self.isExporting = false
                self.exportSuccess = true
                print("成功导出 \(count) 张图片")
                completion(true)
            } catch {
                self.isExporting = false
                self.errorMessage = error.localizedDescription
                print("导出失败: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    func exportSingleFrame(_ frame: CapturedFrame, completion: @escaping (Bool) -> Void) {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil

        Task {
            guard let image = frame.loadFullImage() else {
                self.isExporting = false
                self.errorMessage = "图片读取失败，请重试。"
                completion(false)
                return
            }

            let ext = ExportSettings.shared.format.fileExtension
            let filename = frame.exportFileName(extension: ext)

            do {
                try await imageExportService.exportToPhotoLibrary(image: image, filename: filename)
                self.isExporting = false
                self.exportSuccess = true
                print("成功导出图片")
                completion(true)
            } catch {
                self.isExporting = false
                self.errorMessage = error.localizedDescription
                print("导出失败: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
}
