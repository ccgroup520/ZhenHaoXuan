import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct VideoPickerView: UIViewControllerRepresentable {
    let onVideoSelected: (URL) -> Void
    let onLivePhotoExtracted: ((UIImage, String) -> Void)?
    let onVideoTooLong: () -> Void
    let onError: (String) -> Void
    @Binding var isLoading: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.videos, .livePhotos])
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVideoSelected: onVideoSelected,
            onLivePhotoExtracted: onLivePhotoExtracted,
            onVideoTooLong: onVideoTooLong,
            onError: onError,
            isLoading: $isLoading
        )
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onVideoSelected: (URL) -> Void
        let onLivePhotoExtracted: ((UIImage, String) -> Void)?
        let onVideoTooLong: () -> Void
        let onError: (String) -> Void
        @Binding var isLoading: Bool

        init(
            onVideoSelected: @escaping (URL) -> Void,
            onLivePhotoExtracted: ((UIImage, String) -> Void)?,
            onVideoTooLong: @escaping () -> Void,
            onError: @escaping (String) -> Void,
            isLoading: Binding<Bool>
        ) {
            self.onVideoSelected = onVideoSelected
            self.onLivePhotoExtracted = onLivePhotoExtracted
            self.onVideoTooLong = onVideoTooLong
            self.onError = onError
            self._isLoading = isLoading
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) {
                guard let result = results.first else { return }

                DispatchQueue.main.async {
                    self.isLoading = true
                }

                // 选择新文件前清理旧临时文件
                MediaTempStore.prepareForNewSelection()

                // 判断用户选的是 Live Photo 还是视频
                let isLivePhoto = result.itemProvider.hasItemConformingToTypeIdentifier(
                    UTType.livePhoto.identifier
                )

                if isLivePhoto {
                    self.handleLivePhotoSelection(result)
                } else {
                    self.handleVideoSelection(result)
                }
            }
        }

        // MARK: - Live Photo 处理

        private func handleLivePhotoSelection(_ result: PHPickerResult) {
            guard let assetID = result.assetIdentifier else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onError("无法获取 Live Photo 资源")
                }
                return
            }

            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onError("无法获取 Live Photo 资源")
                }
                return
            }

            Task {
                do {
                    let image = try await LivePhotoExtractorService.shared.extractKeyImage(from: asset)
                    await MainActor.run {
                        self.isLoading = false
                        self.onLivePhotoExtracted?(image, assetID)
                    }
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                        self.onError(error.localizedDescription)
                    }
                }
            }
        }

        // MARK: - 视频处理

        private func handleVideoSelection(_ result: PHPickerResult) {
            if let assetIdentifier = result.assetIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                guard let asset = fetchResult.firstObject else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("无法获取视频资源")
                    }
                    return
                }

                let options = PHVideoRequestOptions()
                options.version = .original
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true

                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
                    guard let urlAsset = avAsset as? AVURLAsset else {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.onError("无法获取视频文件")
                        }
                        return
                    }

                    self.copyAndValidateVideo(sourceURL: urlAsset.url)
                }
            } else {
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.onError("加载视频失败: \(error.localizedDescription)")
                        }
                        return
                    }

                    guard let sourceURL = url else {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.onError("无法获取视频文件")
                        }
                        return
                    }

                    self.copyAndValidateVideo(sourceURL: sourceURL)
                }
            }
        }

        private func copyAndValidateVideo(sourceURL: URL) {
            let destinationURL = MediaTempStore.makeDestinationURL(for: sourceURL)

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onError("复制视频失败: \(error.localizedDescription)")
                }
                return
            }

            Task {
                let asset = AVURLAsset(url: destinationURL)
                do {
                    let loadedDuration = try await asset.load(.duration)
                    let duration = loadedDuration.seconds

                    let canSelectVideo = await MainActor.run {
                        VIPManager.shared.canSelectVideo(duration: duration)
                    }

                    if !canSelectVideo {
                        await MainActor.run {
                            self.isLoading = false
                            self.onVideoTooLong()
                        }
                        return
                    }

                    await MainActor.run {
                        self.isLoading = false
                        self.onVideoSelected(destinationURL)
                    }
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                        self.onError("读取视频信息失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
