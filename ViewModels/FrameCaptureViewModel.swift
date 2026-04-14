import Foundation
import Combine
import UIKit

class FrameCaptureViewModel: ObservableObject {
    @Published var capturedFrames: [CapturedFrame] = []
    @Published var isCapturing = false
    
    private let frameExtractor = FrameExtractorService.shared
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    
    func captureFrame(from videoURL: URL, at time: TimeInterval, videoName: String) {
        isCapturing = true
        feedbackGenerator.prepare()
        
        frameExtractor.extractFrame(from: videoURL, at: time) { [weak self] result in
            guard let self = self else { return }
            
            self.isCapturing = false
            
            switch result {
            case .success(let image):
                let frame = CapturedFrame(
                    image: image,
                    timestamp: time,
                    videoName: videoName
                )
                self.capturedFrames.append(frame)
                
                DispatchQueue.main.async {
                    self.feedbackGenerator.notificationOccurred(.success)
                }
                
            case .failure(let error):
                print("捕获帧失败: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    self.feedbackGenerator.notificationOccurred(.error)
                }
            }
        }
    }
    
    func removeFrame(at index: Int) {
        guard capturedFrames.indices.contains(index) else { return }
        capturedFrames.remove(at: index)
    }

    func removeFrame(id: UUID) {
        capturedFrames.removeAll { $0.id == id }
    }

    func removeFrames(ids: Set<UUID>) {
        capturedFrames.removeAll { ids.contains($0.id) }
    }
    
    func clearAllFrames() {
        capturedFrames.removeAll()
    }
}
