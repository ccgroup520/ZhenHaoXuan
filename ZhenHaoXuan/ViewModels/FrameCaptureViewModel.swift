import Foundation
import Combine
import UIKit

class FrameCaptureViewModel: ObservableObject {
    @Published var capturedFrames: [CapturedFrame] = []
    @Published var isCapturing = false
    
    private let frameExtractor = FrameExtractorService.shared
    private let frameStore = FrameStore.shared
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    init() {
        // App 重启后恢复之前抓过的帧（只加载缩略图）。
        capturedFrames = frameStore.loadAll()
    }

    func captureFrame(from videoURL: URL, at time: TimeInterval, videoName: String) {
        isCapturing = true
        feedbackGenerator.prepare()
        
        frameExtractor.extractFrame(from: videoURL, at: time) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let image):
                // 原图写盘较重，放后台执行，完成后回主线程更新列表。
                DispatchQueue.global(qos: .userInitiated).async {
                    let frame = self.frameStore.add(image: image, timestamp: time, videoName: videoName)
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        if let frame = frame {
                            self.capturedFrames.append(frame)
                            self.feedbackGenerator.notificationOccurred(.success)
                        } else {
                            self.feedbackGenerator.notificationOccurred(.error)
                        }
                    }
                }
                
            case .failure(let error):
                self.isCapturing = false
                print("捕获帧失败: \(error.localizedDescription)")
                self.feedbackGenerator.notificationOccurred(.error)
            }
        }
    }
    
    func removeFrame(at index: Int) {
        guard capturedFrames.indices.contains(index) else { return }
        let id = capturedFrames[index].id
        capturedFrames.remove(at: index)
        deleteFromStore([id])
    }

    func removeFrame(id: UUID) {
        capturedFrames.removeAll { $0.id == id }
        deleteFromStore([id])
    }

    func removeFrames(ids: Set<UUID>) {
        capturedFrames.removeAll { ids.contains($0.id) }
        deleteFromStore(ids)
    }
    
    func clearAllFrames() {
        capturedFrames.removeAll()
        DispatchQueue.global(qos: .utility).async {
            self.frameStore.removeAll()
        }
    }

    /// 后台删除磁盘上的帧文件，避免阻塞主线程。
    private func deleteFromStore(_ ids: Set<UUID>) {
        DispatchQueue.global(qos: .utility).async {
            self.frameStore.remove(ids: ids)
        }
    }
}
