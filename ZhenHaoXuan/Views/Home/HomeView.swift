import SwiftUI

struct HomeView: View {
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var isFromLivePhoto = false
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    @StateObject private var captureViewModel = FrameCaptureViewModel()
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    @ObservedObject private var vipManager = VIPManager.shared

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 40)

                    brandSection

                    actionCard

                    quickStatsCard

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }

            if isLoading {
                loadingOverlay
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerView(
                onVideoSelected: { url in
                    isFromLivePhoto = false
                    selectedVideoURL = url
                },
                onLivePhotoSelected: { url in
                    isFromLivePhoto = true
                    selectedVideoURL = url
                },
                onError: { error in
                    errorMessage = error
                    showErrorAlert = true
                },
                isLoading: $isLoading
            )
        }
        .fullScreenCover(item: $selectedVideoURL) { url in
            VideoPreviewView(
                videoURL: url,
                isFromLivePhoto: isFromLivePhoto,
                viewModel: playerViewModel,
                captureViewModel: captureViewModel,
                onBack: {
                    if let url = selectedVideoURL {
                        MediaTempStore.remove(url)
                    }
                    selectedVideoURL = nil
                }
            )
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Subviews

    private var brandSection: some View {
        VStack(spacing: 16) {
            Image("BrandIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .shadow(color: AppPalette.brandBlue.opacity(0.3), radius: 16, y: 8)

            Text("真好选")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if vipManager.isPaidUser {
                AppPill(
                    title: vipManager.currentTier == .permanent ? "永久会员" : "月度会员",
                    systemImage: "crown.fill",
                    color: AppPalette.brandOrangeDeep
                )
            }
        }
        .frame(maxWidth: .infinity)
        .withPageAnimation()
    }

    private var actionCard: some View {
        Button(action: {
            showVideoPicker = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppPalette.brandBlue, AppPalette.brandBlueDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AppPalette.brandBlue.opacity(0.3), radius: 12, y: 6)

                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("选择视频或 Live Photo")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("快速提取精彩画面")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(AppPressableButtonStyle())
        .withPageAnimation(delay: 0.1)
    }

    private var quickStatsCard: some View {
        HStack(spacing: 16) {
            statItem(
                value: vipManager.isPaidUser ? "∞" : "\(vipManager.remainingExports)",
                label: vipManager.isPaidUser ? "无限导出" : "剩余",
                color: vipManager.isPaidUser ? AppPalette.brandOrangeDeep : AppPalette.brandBlue
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.elevatedSurface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        .withPageAnimation(delay: 0.2)
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 64, height: 64)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [AppPalette.brandSky, AppPalette.brandBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(360 * 0.3))
                        .animation(
                            .linear(duration: 1.2).repeatForever(autoreverses: false),
                            value: isLoading
                        )
                }

                VStack(spacing: 8) {
                    Text("正在加载")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("请稍候...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .transition(.opacity)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
