import SwiftUI
import AVKit
import Combine

struct VideoPreviewView: View {
    let videoURL: URL
    let isFromLivePhoto: Bool
    @ObservedObject var viewModel: VideoPlayerViewModel
    @ObservedObject var captureViewModel: FrameCaptureViewModel
    let onBack: () -> Void

    @State private var showControls = false
    @State private var showGallery = false
    @State private var dominantColor: Color = .black
    @State private var backButtonScale: CGFloat = 1.0
    @State private var galleryButtonScale: CGFloat = 1.0
    @State private var showLongVideoTip = false
    @State private var showPlayGuide = false
    @State private var showCaptureGuide = false
    @State private var hasShownPlayGuide = false
    @State private var hasShownCaptureGuide = false

    var body: some View {
        ZStack {
            VideoBackgroundView(color: dominantColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                videoArea

                bottomControlArea
            }

            controlsOverlay
                .opacity(showControls ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: showControls)
        }
        .statusBarHidden(true)
        .onAppear {
            viewModel.loadVideo(url: videoURL)
            extractDominantColor()

            withAnimation(.easeOut(duration: 0.4)) {
                showControls = true
            }

            // 长视频提示
            if viewModel.duration > 300 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showLongVideoTip = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showLongVideoTip = false
                        }
                    }
                }
            }

            // 新手引导：首次播放时显示"点击画面播放/暂停"
            let hasShownPlay = UserDefaults.standard.bool(forKey: "hasShownPlayGuide")
            if !hasShownPlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showPlayGuide = true
                        hasShownPlayGuide = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showPlayGuide = false
                        }
                        UserDefaults.standard.set(true, forKey: "hasShownPlayGuide")
                    }
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showGallery) {
            FrameGalleryView(
                frames: captureViewModel.capturedFrames,
                onClearAll: {
                    captureViewModel.clearAllFrames()
                },
                onDeleteFrame: { id in
                    captureViewModel.removeFrame(id: id)
                },
                onDeleteFrames: { ids in
                    captureViewModel.removeFrames(ids: ids)
                }
            )
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar

            if showLongVideoTip {
                longVideoTipBanner
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showPlayGuide {
                playGuideBubble
                    .padding(.top, 12)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            backButton

            Spacer()

            HStack(spacing: 8) {
                if isFromLivePhoto {
                    liveBadge
                }
                if viewModel.isHDR {
                    hdrBadge
                }
            }

            Spacer()

            galleryButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var backButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onBack()
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(backButtonScale)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        backButtonScale = 0.9
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        backButtonScale = 1.0
                    }
                }
        )
    }

    private var galleryButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showGallery = true
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .scaleEffect(galleryButtonScale)

                if !captureViewModel.capturedFrames.isEmpty {
                    Text("\(captureViewModel.capturedFrames.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.red)
                        )
                        .shadow(color: .red.opacity(0.5), radius: 4, y: 2)
                        .offset(x: 14, y: -14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        galleryButtonScale = 0.9
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        galleryButtonScale = 1.0
                    }
                }
        )
        .animation(.easeOut(duration: 0.3), value: captureViewModel.capturedFrames.count)
    }

    private var videoArea: some View {
        GeometryReader { _ in
            ZStack {
                if let player = viewModel.player {
                    NativeVideoPlayerView(player: player)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showControls.toggle()
                            }
                        }
                }

                VStack {
                    Spacer()

                    PlaybackControlOverlay(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .clipped()
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "livephoto")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)

            Text("来自 Live Photo")
                .font(.caption.weight(.bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1.5)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private var longVideoTipBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)

            Text("视频较长，拖动进度条可快速定位")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.top, 8)
    }

    private var hdrBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "sun.max.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.yellow)

            Text("HDR")
                .font(.caption.weight(.bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1.5)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private var bottomControlArea: some View {
        FrameActionBar(
            videoURL: videoURL,
            isFromLivePhoto: isFromLivePhoto,
            viewModel: viewModel,
            captureViewModel: captureViewModel,
            showCaptureGuide: $showCaptureGuide,
            hasShownCaptureGuide: $hasShownCaptureGuide
        )
    }

    private var playGuideBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 12))
            Text("点击画面播放/暂停")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

private struct PlaybackControlOverlay: View {
    @ObservedObject var viewModel: VideoPlayerViewModel

    @State private var progress: Double = 0
    @State private var isDragging = false
    @State private var timelineTime: TimeInterval = 0
    @State private var playButtonScale: CGFloat = 1.0
    @State private var muteButtonScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(formatTime(timelineTime))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                if isDragging {
                    Text(formatTime(viewModel.duration))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 6)

            HStack(spacing: 10) {
                playPauseButton

                DraggableProgressBar(
                    progress: $progress,
                    isDragging: $isDragging,
                    duration: viewModel.duration,
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.beginScrubbing()
                        }
                    },
                    onSeek: { time in
                        timelineTime = time
                        viewModel.endScrubbing(at: time)
                    },
                    onScrub: { time in
                        timelineTime = time
                        viewModel.seekForScrubbing(to: time)
                    }
                )

                muteButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .animation(.easeOut(duration: 0.25), value: isDragging)
        .onAppear {
            timelineTime = viewModel.currentTime
            progress = normalizedProgress(for: viewModel.currentTime)
        }
        .onReceive(viewModel.currentTimePublisher) { newTime in
            timelineTime = newTime

            if !isDragging {
                progress = normalizedProgress(for: newTime)
            }
        }
        .onChange(of: viewModel.duration) { _ in
            if !isDragging {
                progress = normalizedProgress(for: timelineTime)
            }
        }
    }

    private var playPauseButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            viewModel.togglePlayPause()
        }) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 42, height: 42)

                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(playButtonScale)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        playButtonScale = 0.88
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        playButtonScale = 1.0
                    }
                }
        )
    }

    private var muteButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            viewModel.toggleMute()
        }) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 42, height: 42)

                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(muteButtonScale)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        muteButtonScale = 0.88
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        muteButtonScale = 1.0
                    }
                }
        )
    }

    private func normalizedProgress(for time: TimeInterval) -> Double {
        guard viewModel.duration > 0 else { return 0 }
        return max(0, min(1, time / viewModel.duration))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let centiseconds = Int((max(0, time) - Double(totalSeconds)) * 100)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        }
    }
}

private struct FrameActionBar: View {
    let videoURL: URL
    let isFromLivePhoto: Bool
    @ObservedObject var viewModel: VideoPlayerViewModel
    @ObservedObject var captureViewModel: FrameCaptureViewModel
    @Binding var showCaptureGuide: Bool
    @Binding var hasShownCaptureGuide: Bool

    @State private var timelineTime: TimeInterval = 0
    @State private var captureButtonScale: CGFloat = 1.0
    @State private var leftStepScale: CGFloat = 1.0
    @State private var rightStepScale: CGFloat = 1.0
    @State private var capturePulse = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            if showCaptureGuide {
                captureGuideToast
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 50) {
                frameStepButton(
                    systemImage: "backward.frame.fill",
                    accessibilityLabel: "上一针",
                    offset: -1,
                    scale: $leftStepScale
                )

                ZStack {
                    captureButton
                }
                .overlay(alignment: .top) {
                    // 捕获数量角标
                    if !captureViewModel.capturedFrames.isEmpty {
                        badgeCount
                    }
                }

                frameStepButton(
                    systemImage: "forward.frame.fill",
                    accessibilityLabel: "下一针",
                    offset: 1,
                    scale: $rightStepScale
                )
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            // 帧序号显示：当前帧 / 总帧数
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                Text("\(viewModel.currentFrameIndex + 1)/\(viewModel.totalFrames)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            timelineTime = viewModel.currentTime
        }
        .onReceive(viewModel.currentTimePublisher) { newTime in
            timelineTime = newTime
        }
        .onChange(of: captureViewModel.isCapturing) { isCapturing in
            if !isCapturing {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                    capturePulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    capturePulse = false
                }
            }
        }
    }

    private var captureButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            captureFrame()
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 2)
                    )
                    .frame(width: 61, height: 61)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 8)

                if captureViewModel.isCapturing {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 4)
                            .frame(width: 42, height: 42)

                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 42, height: 42)
                            .rotationEffect(.degrees(rotationAngle))
                    }
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                    .onDisappear {
                        rotationAngle = 0
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 42, height: 42)
                            .scaleEffect(capturePulse ? 1.15 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: capturePulse)

                        Image(systemName: "camera.aperture")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(captureViewModel.isCapturing)
        .scaleEffect(captureButtonScale)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !captureViewModel.isCapturing {
                        withAnimation(.easeOut(duration: 0.15)) {
                            captureButtonScale = 0.9
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                        captureButtonScale = 1.0
                    }
                }
        )
    }

    private var badgeCount: some View {
        Text("\(captureViewModel.capturedFrames.count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.red)
            )
            .shadow(color: .red.opacity(0.5), radius: 4, y: 2)
            .offset(y: -8)
            .transition(.scale.combined(with: .opacity))
    }

    private var captureGuideToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
            Text("已捕获，可继续抓取更多")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private func captureFrame() {
        let source: FrameSource = isFromLivePhoto
            ? .livePhoto(assetID: videoURL.lastPathComponent)
            : .video(url: videoURL)
        captureViewModel.captureFrame(
            from: videoURL,
            at: timelineTime,
            videoName: videoURL.lastPathComponent,
            source: source
        )

        // 新手引导：首次捕获时显示"已捕获，可继续抓取更多"
        let hasShownCapture = UserDefaults.standard.bool(forKey: "hasShownCaptureGuide")
        if !hasShownCapture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showCaptureGuide = true
                    hasShownCaptureGuide = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showCaptureGuide = false
                    }
                    UserDefaults.standard.set(true, forKey: "hasShownCaptureGuide")
                }
            }
        }
    }

    private func frameStepButton(
        systemImage: String,
        accessibilityLabel: String,
        offset: Int,
        scale: Binding<CGFloat>
    ) -> some View {
        let canStep = viewModel.canStepFrame(from: timelineTime, by: offset)

        return Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            viewModel.stepFrame(by: offset)
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(canStep ? .white.opacity(0.25) : .white.opacity(0.1), lineWidth: 1.5)
                    )
                    .frame(width: 51, height: 51)
                    .shadow(color: .black.opacity(canStep ? 0.3 : 0.1), radius: canStep ? 16 : 8, y: canStep ? 6 : 3)

                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(canStep ? .white : .white.opacity(0.4))
                    .scaleEffect(scale.wrappedValue)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!canStep)
        .opacity(canStep ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if canStep {
                        withAnimation(.easeOut(duration: 0.15)) {
                            scale.wrappedValue = 0.88
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        scale.wrappedValue = 1.0
                    }
                }
        )
    }
}

private func formatFrameRate(_ frameRate: Double) -> String {
    if frameRate.rounded() == frameRate {
        return String(Int(frameRate))
    }

    return String(format: "%.2f", frameRate)
}

struct NativeVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.update(player: player)
    }
}

class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.needsDisplayOnBoundsChange = true
        
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func update(player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }
}

struct VideoPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPreviewView(
            videoURL: URL(string: "file://test.mp4")!,
            isFromLivePhoto: false,
            viewModel: VideoPlayerViewModel(),
            captureViewModel: FrameCaptureViewModel(),
            onBack: {}
        )
    }
}

struct VideoBackgroundView: View {
    let color: Color
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)

            color
                .opacity(0.35)
                .blendMode(.softLight)

            Circle()
                .fill(color.opacity(0.28))
                .blur(radius: 100)
                .scaleEffect(animateGradient ? 1.6 : 1.3)
                .offset(x: animateGradient ? -80 : -120, y: animateGradient ? -180 : -220)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateGradient)

            Circle()
                .fill(color.opacity(0.24))
                .blur(radius: 80)
                .scaleEffect(animateGradient ? 1.4 : 1.1)
                .offset(x: animateGradient ? 100 : 60, y: animateGradient ? 130 : 170)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true).delay(1), value: animateGradient)

            Circle()
                .fill(color.opacity(0.17))
                .blur(radius: 60)
                .scaleEffect(animateGradient ? 1.2 : 0.9)
                .offset(x: animateGradient ? -60 : -20, y: animateGradient ? 220 : 180)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true).delay(2), value: animateGradient)
        }
        .background(.ultraThinMaterial.opacity(0.7))
        .onAppear {
            animateGradient = true
        }
    }
}

extension VideoPreviewView {
    private func extractDominantColor() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 100, height: 100)
            
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                if let dominant = uiImage.dominantColor() {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.dominantColor = dominant
                        }
                    }
                }
            } catch {
                print("提取视频颜色失败: \(error.localizedDescription)")
            }
        }
    }
}

extension UIImage {
    private static let dominantColorContext = CIContext(options: [.workingColorSpace: kCFNull as Any])

    func dominantColor() -> Color? {
        guard let inputImage = CIImage(image: self) else { return nil }
        
        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )
        
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]
        ),
              let outputImage = filter.outputImage else {
            return nil
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)

        let context = Self.dominantColorContext
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        
        return Color(
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
    }
}
