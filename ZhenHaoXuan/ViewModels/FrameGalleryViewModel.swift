import Foundation
import Combine

class FrameGalleryViewModel: ObservableObject {
    @Published var isExporting = false
    @Published var exportSuccess = false
    @Published var errorMessage: String?
    
    private let imageExportService = ImageExportService.shared
    
    func exportFrames(_ frames: [CapturedFrame], completion: @escaping (Bool) -> Void) {
        isExporting = true
        errorMessage = nil
        
        // 导出时才按需从磁盘读取原图，避免一直占用内存。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let images = frames.compactMap { $0.loadFullImage() }

            guard images.count == frames.count, !images.isEmpty else {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.errorMessage = "图片读取失败，请重试。"
                    completion(false)
                }
                return
            }

            self.imageExportService.exportMultipleToPhotoLibrary(images: images) { result in
                self.isExporting = false

                switch result {
                case .success(let count):
                    self.exportSuccess = true
                    print("成功导出 \(count) 张图片")
                    completion(true)

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("导出失败: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
    
    func exportSingleFrame(_ frame: CapturedFrame, completion: @escaping (Bool) -> Void) {
        isExporting = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let image = frame.loadFullImage() else {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.errorMessage = "图片读取失败，请重试。"
                    completion(false)
                }
                return
            }

            self.imageExportService.exportToPhotoLibrary(image: image) { result in
                self.isExporting = false

                switch result {
                case .success:
                    self.exportSuccess = true
                    print("成功导出图片")
                    completion(true)

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("导出失败: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
}
