import Foundation
import Combine
import UIKit

@MainActor
final class FrameCaptureViewModel: ObservableObject {
    @Published var capturedFrames: [CapturedFrame] = []
    @Published var isCapturing = false

    private let frameExtractor = FrameExtractorService.shared
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    init() {
        // App 重启后恢复之前抓过的帧（只加载缩略图）
        Task {
            capturedFrames = await FrameStore.shared.loadAll()
        }
    }

    func captureFrame(from videoURL: URL, at time: TimeInterval, videoName: String) {
        guard !isCapturing else { return }
        isCapturing = true
        feedbackGenerator.prepare()

        Task {
            do {
                let image = try await frameExtractor.extractFrame(from: videoURL, at: time)

                // 原图写盘较重，在 actor 内部执行（自动排队不冲突）
                let frame = await FrameStore.shared.add(
                    image: image,
                    timestamp: time,
                    videoName: videoName,
                    source: .video(url: videoURL)
                )

                self.isCapturing = false
                if let frame = frame {
                    self.capturedFrames.append(frame)
                    self.feedbackGenerator.notificationOccurred(.success)
                } else {
                    self.feedbackGenerator.notificationOccurred(.error)
                }
            } catch {
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
        Task {
            await FrameStore.shared.removeAll()
        }
    }

    /// 后台删除磁盘上的帧文件
    private func deleteFromStore(_ ids: Set<UUID>) {
        Task {
            await FrameStore.shared.remove(ids: ids)
        }
    }
}
