import Foundation
import Photos
import UIKit
import ImageIO

/// 图片导出服务。
///
/// 通俗解释：这是"打印店"，把 App 里捕获的图片"打印"到系统相册。
/// 支持单张/批量打印，PNG/JPEG 格式，可调质量。
actor ImageExportService {
    static let shared = ImageExportService()


    private init() {}

    func exportToPhotoLibrary(image: UIImage, filename: String) async throws {
        try await requestAddOnlyAuthorization()

        guard let encoded = await encodedImage(from: image, filename: filename) else {
            throw ImageExportError.encodingFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = encoded.filename
            request.addResource(with: .photo, data: encoded.data, options: options)
        }
    }

    func exportMultipleToPhotoLibrary(images: [(image: UIImage, filename: String)]) async throws -> Int {
        guard !images.isEmpty else { return 0 }

        try await requestAddOnlyAuthorization()

        let encodedImages: [EncodedImage] = await withTaskGroup(of: (Int, EncodedImage?).self) { group in
            for (index, item) in images.enumerated() {
                group.addTask {
                    let encoded = await self.encodedImage(from: item.image, filename: item.filename)
                    return (index, encoded)
                }
            }

            var results = [(Int, EncodedImage)]()
            for await (index, encoded) in group {
                if let encoded = encoded {
                    results.append((index, encoded))
                }
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        guard encodedImages.count == images.count else {
            throw ImageExportError.encodingFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            for encoded in encodedImages {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = encoded.filename
                request.addResource(with: .photo, data: encoded.data, options: options)
            }
        }

        return encodedImages.count
    }

    // MARK: - Private

    private func requestAddOnlyAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        default:
            throw ImageExportError.permissionDenied
        }
    }

    private func encodedImage(from image: UIImage, filename: String) async -> EncodedImage? {
        let (format, quality) = await MainActor.run {
            (ExportSettings.shared.format, ExportSettings.shared.quality.compressionQuality)
        }

        switch format {
        case .png:
            if let data = createPNGData(from: image) {
                return EncodedImage(data: data, filename: filename)
            }
            return nil

        case .jpeg:
            if let data = createJPEGData(from: image, quality: quality) {
                return EncodedImage(data: data, filename: filename)
            }
            return nil
        }
    }

    private func createJPEGData(from image: UIImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else {
            return image.jpegData(compressionQuality: quality)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return image.jpegData(compressionQuality: quality)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        if CGImageDestinationFinalize(destination) {
            return data as Data
        }

        return image.jpegData(compressionQuality: quality)
    }

    private func createPNGData(from image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return image.pngData() }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return image.pngData()
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            return data as Data
        }

        return image.pngData()
    }
}

// MARK: - Supporting Types

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
