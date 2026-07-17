import Foundation
import AVFoundation
import Combine

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published var isMuted = false
    @Published var videoURL: URL?
    @Published var frameRate: Double = 30
    @Published var isHDR = false

    private(set) var currentTime: TimeInterval = 0
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    private var timeObserver: Any?
    private var isSeekInProgress = false
    private var pendingSeekTime: TimeInterval?
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private var isScrubbing = false
    private var shouldResumePlaybackAfterScrubbing = false

    var frameDuration: TimeInterval {
        guard frameRate > 0 else { return 1 / 30 }
        return 1 / frameRate
    }

    var totalFrames: Int {
        guard duration > 0, frameRate > 0 else { return 0 }
        return max(Int(round(duration * frameRate)), 1)
    }

    var currentFrameIndex: Int {
        frameIndex(for: currentTime)
    }

    func loadVideo(url: URL) {
        let asset = AVURLAsset(url: url)
        cleanup()
        videoURL = url

        Task {
            do {
                let durationValue = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                let (detectedFrameRate, hdrDetected) = await (
                    Self.resolveFrameRate(from: tracks.first),
                    Self.detectHDR(from: tracks.first)
                )

                duration = durationValue.seconds
                frameRate = detectedFrameRate
                isHDR = hdrDetected

                let playerItem = AVPlayerItem(asset: asset)
                if ExportSettings.shared.hdrEnabled {
                    playerItem.preferredMaximumResolution = CGSize(width: 4096, height: 4096)
                }

                player = AVPlayer(playerItem: playerItem)
                addPeriodicTimeObserver()
            } catch {
                print("加载视频失败: \(error.localizedDescription)")
            }
        }
    }

    private static func detectHDR(from track: AVAssetTrack?) async -> Bool {
        guard let track else { return false }

        do {
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDescription = formatDescriptions.first else { return false }

            let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any]

            if let colorPrimaries = extensions?[kCVImageBufferColorPrimariesKey as String] as? String {
                if colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                    return true
                }
            }

            if let transferFunction = extensions?[kCVImageBufferTransferFunctionKey as String] as? String {
                if transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) ||
                   transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
                    return true
                }
            }

            return false
        } catch {
            return false
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: CMTimeScale(600))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.updateCurrentTime(to: time.seconds)
        }
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func seek(to time: TimeInterval) {
        let bufferTime: TimeInterval = 0.01
        let clampedTime = max(0, min(time, duration - bufferTime))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(600))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateCurrentTime(to: clampedTime)
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        pendingSeekTime = nil
        shouldResumePlaybackAfterScrubbing = player?.timeControlStatus == .playing || isPlaying
        if shouldResumePlaybackAfterScrubbing { player?.pause() }
    }

    func seekForScrubbing(to time: TimeInterval) {
        let bufferTime: TimeInterval = 0.01
        let clampedTime = max(0, min(time, duration - bufferTime))
        updateCurrentTime(to: clampedTime)

        if isSeekInProgress {
            pendingSeekTime = clampedTime
            return
        }

        performScrubbingSeek(to: clampedTime)
    }

    private func performScrubbingSeek(to time: TimeInterval) {
        guard let player else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(600))
        let tolerance = scrubTolerance
        isSeekInProgress = true

        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard let self else { return }
            self.isSeekInProgress = false
            if let pending = self.pendingSeekTime {
                self.pendingSeekTime = nil
                self.performScrubbingSeek(to: pending)
            }
        }
    }

    func endScrubbing(at time: TimeInterval) {
        isScrubbing = false
        seekPrecise(to: time, resumePlaybackIfNeeded: true)
    }

    func seekPrecise(to time: TimeInterval, resumePlaybackIfNeeded: Bool = false) {
        let bufferTime: TimeInterval = 0.01
        let clampedTime = max(0, min(time, duration - bufferTime))
        updateCurrentTime(to: clampedTime)
        pendingSeekTime = nil

        guard let player else { return }
        player.currentItem?.cancelPendingSeeks()

        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(600))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.updateCurrentTime(to: clampedTime)
            if resumePlaybackIfNeeded, self.shouldResumePlaybackAfterScrubbing {
                player.play()
            }
            self.shouldResumePlaybackAfterScrubbing = false
        }
    }

    func stepFrame(by offset: Int) {
        guard totalFrames > 0 else { return }
        let targetFrame = min(max(currentFrameIndex + offset, 0), totalFrames - 1)
        seek(toFrame: targetFrame)
    }

    func seek(toFrame frameIndex: Int) {
        guard totalFrames > 0 else { return }
        let clampedFrame = min(max(frameIndex, 0), totalFrames - 1)
        let targetTime = Double(clampedFrame) * frameDuration
        seek(to: min(targetTime, duration))
    }

    func canStepFrame(by offset: Int) -> Bool {
        canStepFrame(from: currentTime, by: offset)
    }

    func canStepFrame(from time: TimeInterval, by offset: Int) -> Bool {
        guard totalFrames > 0 else { return false }
        let targetFrame = frameIndex(for: time) + offset
        return (0..<totalFrames).contains(targetFrame)
    }

    func frameIndex(for time: TimeInterval) -> Int {
        guard totalFrames > 0 else { return 0 }
        let rawFrame = Int(round(max(0, time) * frameRate))
        return min(max(rawFrame, 0), totalFrames - 1)
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // 清理帧提取器的 generator 缓存，释放资源
        if let url = videoURL {
            Task { await FrameExtractorService.shared.clearCache(for: url) }
        }
        player?.pause()
        player = nil
        isPlaying = false
        isSeekInProgress = false
        pendingSeekTime = nil
        isScrubbing = false
        shouldResumePlaybackAfterScrubbing = false
        duration = 0
        frameRate = 30
        videoURL = nil
        updateCurrentTime(to: 0)
    }

    nonisolated deinit {
        // @MainActor class deinit runs nonisolated; cleanup is handled by caller via .onDisappear
    }

    private static func resolveFrameRate(from track: AVAssetTrack?) async -> Double {
        guard let track else { return 30 }

        do {
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            if nominalFrameRate > 0 { return Double(nominalFrameRate) }

            let minFrameDuration = try await track.load(.minFrameDuration)
            if minFrameDuration.isValid && minFrameDuration.seconds > 0 {
                return 1.0 / minFrameDuration.seconds
            }

            let timeRange = try await track.load(.timeRange)
            let duration = timeRange.duration.seconds
            if duration > 0 { return 60.0 }
        } catch {
            print("帧率检测失败: \(error.localizedDescription)")
        }

        return 30
    }

    private var scrubTolerance: CMTime {
        let toleranceSeconds = max(frameDuration * 0.5, 1.0 / 120.0)
        return CMTime(seconds: toleranceSeconds, preferredTimescale: CMTimeScale(600))
    }

    private func updateCurrentTime(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration > 0 ? duration : time))
        currentTime = clampedTime
        currentTimeSubject.send(clampedTime)
    }
}
