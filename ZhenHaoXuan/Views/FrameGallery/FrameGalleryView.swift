import SwiftUI

struct FrameGalleryView: View {
    let frames: [CapturedFrame]
    let onClearAll: () -> Void
    let onDeleteFrame: (UUID) -> Void
    let onDeleteFrames: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FrameGalleryViewModel()
    @ObservedObject private var vipManager = VIPManager.shared
    @State private var selectedFrames: Set<UUID> = []
    @State private var showExportSuccess = false
    @State private var showExportLimitAlert = false
    @State private var showVIPUpgradeAlert = false
    @State private var showDeleteConfirm = false
    @State private var showClearAllConfirm = false
    @State private var pendingExportCount = 0
    @State private var appeared = false
    /// 记录当前正在进行的导出操作需要多少张额度
    @State private var activeExportCount: Int = 0

    private var gridItemLayout: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 16)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if frames.isEmpty {
                    emptyState
                        .padding(.horizontal, 32)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            headerCard
                            frameGrid
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }

                exportingOverlay
            }
            .navigationTitle(frames.isEmpty ? "" : "捕获的帧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !frames.isEmpty {
                        toolbarMenu
                    }
                }
            }
            .alert("导出成功", isPresented: $showExportSuccess) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("图片已保存到相册")
            }
            .alert("导出次数限制", isPresented: $showExportLimitAlert) {
                Button("取消", role: .cancel) {
                    vipManager.releaseExportQuota(count: activeExportCount)
                    activeExportCount = 0
                }
                Button("升级会员") { showVIPUpgradeAlert = true }
            } message: {
                if vipManager.isPaidUser {
                    Text("导出失败，请重试")
                } else {
                    Text("本次需要导出\(pendingExportCount)张，普通用户今日还剩\(vipManager.remainingExports)张。")
                }
            }
            .alert("导出失败", isPresented: exportErrorBinding) {
                Button("确定", role: .cancel) {
                    viewModel.errorMessage = nil
                    vipManager.releaseExportQuota(count: activeExportCount)
                    activeExportCount = 0
                }
            } message: {
                Text(viewModel.errorMessage ?? "导出失败，请稍后重试。")
            }
           .sheet(isPresented: $showVIPUpgradeAlert) {
               VIPMembershipView()
           }
           .alert("确认删除", isPresented: $showDeleteConfirm) {
               Button("取消", role: .cancel) {}
               Button("删除", role: .destructive) { deleteSelectedFrames() }
           } message: {
               Text("确定要删除选中的 \(selectedFrames.count) 张图片吗？")
           }
           .alert("确认清空", isPresented: $showClearAllConfirm) {
               Button("取消", role: .cancel) {}
               Button("清空全部", role: .destructive) { clearAll() }
           } message: {
               Text("确定要清空所有捕获的图片吗？此操作不可撤销。")
           }
        }
    }

    private var toolbarMenu: some View {
        Menu {
            Button(action: checkAndExportSelected) {
                Label("导出选中", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedFrames.isEmpty)

            Button(action: checkAndExportAll) {
                Label("导出全部", systemImage: "square.and.arrow.up.on.square")
            }

            if !selectedFrames.isEmpty {
                Divider()
                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("删除选中", systemImage: "trash")
                }
            }

            Divider()

            Button(role: .destructive, action: { showClearAllConfirm = true }) {
                Label("清空全部", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
        }
    }

    private var exportingOverlay: some View {
        Group {
            if viewModel.isExporting {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.6)
                            .tint(.white)

                        Text("正在导出...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(AppPalette.brandBlue.opacity(0.12))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(AppPalette.brandSky.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "photo.stack")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(AppPalette.brandBlue)
            }

            VStack(spacing: 10) {
                Text("还没有捕获任何帧")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("返回视频预览界面，点击捕获按钮来提取画面")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
    }

    private var headerCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(frames.count) 张图片")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(selectedFrames.count == 0 ? "轻点选择" : "已选择 \(selectedFrames.count) 张")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                membershipBadge
            }

            if selectedFrames.count > 0 {
                selectionToolbar
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.bar)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private var membershipBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: vipManager.isPaidUser ? "crown.fill" : "square.and.arrow.down")
                .font(.caption)

            Text(vipManager.isPaidUser ? "无限导出" : "剩余 \(vipManager.remainingExports) 张")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(vipManager.isPaidUser ? AppPalette.brandOrangeDeep : AppPalette.brandBlueDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(vipManager.isPaidUser ? AppPalette.brandOrange.opacity(0.15) : AppPalette.brandBlue.opacity(0.12))
        )
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: checkAndExportSelected) {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brandBlue)

            Button(action: selectAll) {
                Text(selectedFrames.count == frames.count ? "取消全选" : "全选")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var frameGrid: some View {
        LazyVGrid(columns: gridItemLayout, spacing: 16) {
            ForEach(frames) { frame in
                FrameItemView(
                    frame: frame,
                    isSelected: selectedFrames.contains(frame.id),
                    isEditing: selectedFrames.count > 0,
                    onTap: { toggleSelection(frame.id) },
                    onExport: { checkAndExportSingle(frame) },
                    onDelete: { deleteSingleFrame(frame.id) }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in if !newValue { viewModel.errorMessage = nil } }
        )
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedFrames.contains(id) {
            selectedFrames.remove(id)
        } else {
            selectedFrames.insert(id)
        }
    }

    private func selectAll() {
        if selectedFrames.count == frames.count {
            selectedFrames.removeAll()
        } else {
            selectedFrames = Set(frames.map { $0.id })
        }
    }

    // MARK: - Export with Reserve Pattern

    /// 导出流程：预扣额度 → 执行导出 → 确认/释放
    /// 像银行取钱：先冻结余额 → 取款 → 成功则扣款，失败则解冻

    private func checkAndExportSelected() {
        let framesToExport = frames.filter { selectedFrames.contains($0.id) }
        guard !framesToExport.isEmpty else { return }
        checkExportLimit(count: framesToExport.count) {
            exportSelected(framesToExport)
        }
    }

    private func checkAndExportAll() {
        guard !frames.isEmpty else { return }
        checkExportLimit(count: frames.count) {
            exportAll()
        }
    }

    private func checkAndExportSingle(_ frame: CapturedFrame) {
        checkExportLimit(count: 1) {
            exportSingle(frame)
        }
    }

    /// 预扣模式：先冻结额度，成功再扣款，失败则释放
    private func checkExportLimit(count: Int, performExport: @escaping () -> Void) {
        // 永久会员直接放行
        if vipManager.isPaidUser {
            performExport()
            return
        }

        // 尝试预扣额度
        guard vipManager.reserveExportQuota(count: count) else {
            pendingExportCount = count
            activeExportCount = count
            showExportLimitAlert = true
            return
        }

        activeExportCount = count
        performExport()
    }

    private func exportSelected(_ framesToExport: [CapturedFrame]) {
        viewModel.exportFrames(framesToExport) { success in
            if success {
                vipManager.confirmExport(count: framesToExport.count)
                activeExportCount = 0
                showExportSuccess = true
                selectedFrames.removeAll()
            } else {
                vipManager.releaseExportQuota(count: framesToExport.count)
                activeExportCount = 0
            }
        }
    }

    private func exportAll() {
        viewModel.exportFrames(frames) { success in
            if success {
                vipManager.confirmExport(count: frames.count)
                activeExportCount = 0
                showExportSuccess = true
            } else {
                vipManager.releaseExportQuota(count: frames.count)
                activeExportCount = 0
            }
        }
    }

    private func exportSingle(_ frame: CapturedFrame) {
        viewModel.exportSingleFrame(frame) { success in
            if success {
                vipManager.confirmExport(count: 1)
                activeExportCount = 0
                showExportSuccess = true
            } else {
                vipManager.releaseExportQuota(count: 1)
                activeExportCount = 0
            }
        }
    }

    private func deleteSingleFrame(_ id: UUID) {
        selectedFrames.remove(id)
        onDeleteFrame(id)
    }

    private func deleteSelectedFrames() {
        let ids = selectedFrames
        guard !ids.isEmpty else { return }
        onDeleteFrames(ids)
        selectedFrames.removeAll()
    }

    private func clearAll() {
        onClearAll()
        selectedFrames.removeAll()
        dismiss()
    }
}

struct FrameItemView: View {
    let frame: CapturedFrame
    let isSelected: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                imageContent
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("捕获于 \(frame.videoName) 的图片")
            .accessibilityHint(isEditing ? (isSelected ? "再次点击取消选择" : "点击选择") : "点击选择或导出")

            selectionIndicator
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .contextMenu {
            Button(action: onExport) {
                Label("导出到相册", systemImage: "square.and.arrow.up")
            }

            Button(action: onTap) {
                Label(isSelected ? "取消选择" : "选择", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var imageContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: frame.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()

                gradientOverlay

                infoOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? AppPalette.brandBlue : Color.white.opacity(0.5),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                if case .livePhoto = frame.source {
                    livePhotoBadge
                }
            }
        }
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.02),
                Color.black.opacity(0.65)
            ],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(frame.videoName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                }

            HStack(spacing: 8) {
                infoTag(text: formatTimestamp(frame.timestamp), systemImage: "clock")
                infoTag(text: formatCaptureDate(frame.captureDate), systemImage: "calendar")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoTag(text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))

            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.2), in: Capsule())
    }

    private var selectionIndicator: some View {
        Group {
            if isSelected {
                Circle()
                    .fill(AppPalette.brandBlue)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: AppPalette.brandBlue.opacity(0.4), radius: 4, y: 2)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let totalSeconds = Int(timestamp.rounded())
        let centiseconds = Int((timestamp - Double(totalSeconds)) * 100)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    private func formatCaptureDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private var livePhotoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "livephoto")
                .font(.system(size: 10))
            Text("Live")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
