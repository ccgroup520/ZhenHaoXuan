import Foundation
import Photos
import UIKit
import ImageIO
import MobileCoreServices

class ImageExportService {
    static let shared = ImageExportService()
    
    private let exportSettings = ExportSettings.shared
    
    private init() {}
    
    func exportToPhotoLibrary(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        requestAddOnlyAuthorization { [weak self] authResult in
            guard let self else { return }

            switch authResult {
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            case .success:
                guard let encodedImage = self.encodedImage(from: image, index: 0) else {
                    DispatchQueue.main.async {
                        completion(.failure(ImageExportError.encodingFailed))
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = encodedImage.filename
                    request.addResource(with: .photo, data: encodedImage.data, options: options)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            completion(.success(()))
                        } else {
                            completion(.failure(error ?? ImageExportError.exportFailed))
                        }
                    }
                }
            }
        }
    }
    
    func exportMultipleToPhotoLibrary(images: [UIImage], completion: @escaping (Result<Int, Error>) -> Void) {
        guard !images.isEmpty else {
            DispatchQueue.main.async {
                completion(.success(0))
            }
            return
        }

        requestAddOnlyAuthorization { [weak self] authResult in
            guard let self else { return }

            switch authResult {
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            case .success:
                let encodedImages = images.enumerated().compactMap { index, image in
                    self.encodedImage(from: image, index: index)
                }

                guard encodedImages.count == images.count else {
                    DispatchQueue.main.async {
                        completion(.failure(ImageExportError.encodingFailed))
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    for encodedImage in encodedImages {
                        let request = PHAssetCreationRequest.forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.originalFilename = encodedImage.filename
                        request.addResource(with: .photo, data: encodedImage.data, options: options)
                    }
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            completion(.success(encodedImages.count))
                        } else {
                            completion(.failure(error ?? ImageExportError.exportFailed))
                        }
                    }
                }
            }
        }
    }
    
    private func requestAddOnlyAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                completion(.success(()))
            default:
                completion(.failure(ImageExportError.permissionDenied))
            }
        }
    }

    private func encodedImage(from image: UIImage, index: Int) -> EncodedImage? {
        let format = exportSettings.format
        let quality = exportSettings.quality
        let preserveMetadata = exportSettings.hdrEnabled
        
        switch format {
        case .png:
            if let data = createPNGData(from: image, preserveMetadata: preserveMetadata) {
                return EncodedImage(data: data, filename: "frame-\(index + 1).png")
            }
            return nil
            
        case .jpeg:
            let compressionQuality = quality.compressionQuality
            if let data = createJPEGData(from: image, quality: compressionQuality, preserveMetadata: preserveMetadata) {
                return EncodedImage(data: data, filename: "frame-\(index + 1).jpg")
            }
            return nil
        }
    }
    
    private func createJPEGData(from image: UIImage, quality: CGFloat, preserveMetadata: Bool) -> Data? {
        guard let cgImage = image.cgImage else { return image.jpegData(compressionQuality: quality) }
        
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return image.jpegData(compressionQuality: quality)
        }
        
        let options: [CFString: Any]
        if preserveMetadata {
            options = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImagePropertyJFIFDictionary: [
                    kCGImagePropertyJFIFVersion: 1,
                    kCGImagePropertyJFIFDensityUnit: 1,
                    kCGImagePropertyJFIFXDensity: 72,
                    kCGImagePropertyJFIFYDensity: 72
                ] as [CFString: Any],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "Extracted with ZhenHaoXuan"
                ] as [CFString: Any]
            ]
        } else {
            options = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
        }
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        if CGImageDestinationFinalize(destination) {
            return data as Data
        }
        
        return image.jpegData(compressionQuality: quality)
    }
    
    private func createPNGData(from image: UIImage, preserveMetadata: Bool) -> Data? {
        guard let cgImage = image.cgImage else { return image.pngData() }
        
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return image.pngData()
        }
        
        let options: [CFString: Any]
        if preserveMetadata {
            options = [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyPNGDescription: "Extracted with ZhenHaoXuan"
                ] as [CFString: Any]
            ]
        } else {
            options = [:]
        }
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        if CGImageDestinationFinalize(destination) {
            return data as Data
        }
        
        return image.pngData()
    }
}

private struct EncodedImage {
    let data: Data
    let filename: String
}

private enum ImageExportError: LocalizedError {
    case permissionDenied
    case encodingFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得保存到相册的权限，请在系统设置中允许访问照片。"
        case .encodingFailed:
            return "图片处理失败，请重试。"
        case .exportFailed:
            return "保存图片失败，请稍后再试。"
        }
    }
}