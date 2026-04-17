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
        
        let images = frames.map { $0.image }
        
        imageExportService.exportMultipleToPhotoLibrary(images: images) { [weak self] result in
            guard let self = self else { return }
            
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
    
    func exportSingleFrame(_ frame: CapturedFrame, completion: @escaping (Bool) -> Void) {
        isExporting = true
        errorMessage = nil
        
        imageExportService.exportToPhotoLibrary(image: frame.image) { [weak self] result in
            guard let self = self else { return }
            
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
