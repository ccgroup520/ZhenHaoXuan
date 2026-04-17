import Foundation
import AVFoundation
import UIKit
import ImageIO

class FrameExtractorService {
    static let shared = FrameExtractorService()
    
    private init() {}
    
    func extractFrame(from videoURL: URL, at time: TimeInterval, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let exportSettings = ExportSettings.shared
        if exportSettings.hdrEnabled {
            imageGenerator.requestedTimeToleranceAfter = .zero
            imageGenerator.requestedTimeToleranceBefore = .zero
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { [weak self] requestedTime, cgImage, actualTime, result, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let cgImage = cgImage else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FrameExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法生成图片"])))
                }
                return
            }
            
            let image = UIImage(cgImage: cgImage)
            
            if exportSettings.hdrEnabled {
                Task {
                    if let hdrImage = await self?.extractHDRFrame(from: asset, at: actualTime) {
                        await MainActor.run {
                            completion(.success(hdrImage))
                        }
                    } else {
                        await MainActor.run {
                            completion(.success(image))
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.success(image))
                }
            }
        }
    }
    
    private func extractHDRFrame(from asset: AVURLAsset, at time: CMTime) async -> UIImage? {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let preferredTransform = try? await videoTrack.load(.preferredTransform)
        
        guard let size = naturalSize else { return nil }
        
        let transform = preferredTransform ?? .identity
        var outputSize = size
        if transform.a == 0 && (transform.b == 1 || transform.b == -1) && (transform.c == 1 || transform.c == -1) {
            outputSize = CGSize(width: size.height, height: size.width)
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.maximumSize = CGSize(width: outputSize.width * 2, height: outputSize.height * 2)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    func extractFrameWithMetadata(from videoURL: URL, at time: TimeInterval, completion: @escaping (Result<(UIImage, [String: Any]?), Error>) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        
        Task {
            do {
                let metadata = try? await asset.load(.metadata)
                let metadataDict = metadata?.reduce(into: [String: Any]()) { result, item in
                    if let key = item.commonKey?.rawValue {
                        result[key] = item.value
                    }
                }
                
                extractFrame(from: videoURL, at: time) { result in
                    switch result {
                    case .success(let image):
                        completion(.success((image, metadataDict)))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}