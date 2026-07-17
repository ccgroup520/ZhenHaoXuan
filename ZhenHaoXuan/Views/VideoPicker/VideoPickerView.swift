import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import Photos

struct VideoPickerView: UIViewControllerRepresentable {
    let onVideoSelected: (URL) -> Void
    let onLivePhotoSelected: (URL) -> Void
    let onError: (String) -> Void
    @Binding var isLoading: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.videos, .livePhotos])
        configuration.preferredAssetRepresentationMode = .automatic

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVideoSelected: onVideoSelected,
            onLivePhotoSelected: onLivePhotoSelected,
            onError: onError,
            isLoading: $isLoading
        )
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onVideoSelected: (URL) -> Void
        let onLivePhotoSelected: (URL) -> Void
        let onError: (String) -> Void
        @Binding var isLoading: Bool

        init(
            onVideoSelected: @escaping (URL) -> Void,
            onLivePhotoSelected: @escaping (URL) -> Void,
            onError: @escaping (String) -> Void,
            isLoading: Binding<Bool>
        ) {
            self.onVideoSelected = onVideoSelected
            self.onLivePhotoSelected = onLivePhotoSelected
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

        /// 从 Live Photo 中提取视频部分（MOV），交给视频流程处理
        private func handleLivePhotoSelection(_ result: PHPickerResult) {
            // 优先使用 PHAsset 路径（更可靠：能获取完整视频，支持 iCloud）
            if let assetIdentifier = result.assetIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: PHFetchOptions())
                if let asset = fetchResult.firstObject {
                    loadLivePhotoVideo(asset: asset)
                    return
                }
            }
            // 降级：使用 itemProvider 方式（不需要相册权限）
            loadLivePhotoMovie(result)
        }

        /// 通过 PHAssetResource 提取 Live Photo 的视频部分（正确方式）
        private func loadLivePhotoVideo(asset: PHAsset) {
            let resources = PHAssetResource.assetResources(for: asset)
            // 查找 paired_video 资源（Live Photo 的视频部分）
            guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onError("无法找到 Live Photo 的视频部分")
                }
                return
            }

            let destinationURL = MediaTempStore.directory.appendingPathComponent("\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_"))_live.mov")

            // 确保目标目录存在
            do {
                try FileManager.default.createDirectory(at: MediaTempStore.directory, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onError("创建临时目录失败: \(error.localizedDescription)")
                }
                return
            }

            // 如果目标已存在，先删除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(for: videoResource, toFile: destinationURL, options: options) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("提取 Live Photo 视频失败: \(error.localizedDescription)")
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.isLoading = false
                    self.onLivePhotoSelected(destinationURL)
                }
            }
        }

        /// 通过 loadFileRepresentation 加载 Live Photo 的视频部分（降级方案）
        private func loadLivePhotoMovie(_ result: PHPickerResult) {
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    // 如果 PHAsset 路径也走过了且失败了，静默处理；否则报错
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("无法获取 Live Photo 视频文件")
                    }
                    return
                }

                guard let sourceURL = url else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("无法获取 Live Photo 视频文件")
                    }
                    return
                }

                let destinationURL = MediaTempStore.makeDestinationURL(for: sourceURL)
                do {
                    // 确保目标目录存在
                    try FileManager.default.createDirectory(
                        at: MediaTempStore.directory,
                        withIntermediateDirectories: true
                    )
                    // 如果目标已存在，先删除
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onLivePhotoSelected(destinationURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("复制 Live Photo 视频失败: \(error.localizedDescription)")
                    }
                }
            }
        }

        // MARK: - 视频处理

        private func handleVideoSelection(_ result: PHPickerResult) {
            if let assetIdentifier = result.assetIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: PHFetchOptions())
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

                    self.copyVideo(sourceURL: urlAsset.url)
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

                    self.copyVideo(sourceURL: sourceURL)
                }
            }
        }

        private func copyVideo(sourceURL: URL) {
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

            DispatchQueue.main.async {
                self.isLoading = false
                self.onVideoSelected(destinationURL)
            }
        }
    }
}
