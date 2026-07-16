import SwiftUI
import StoreKit

struct VIPMembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vipManager = VIPManager.shared

    @State private var showSuccessAlert = false
    @State private var showRestoreSuccessAlert = false
    @State private var activeDocument: PolicyDocument?
    @State private var selectedPlan: PlanType = .permanent

    enum PlanType: String, CaseIterable {
        case monthly = "月度会员"
        case yearly = "年度会员"
        case permanent = "终身会员"

        var price: String {
            switch self {
            case .monthly: return "¥6.00"
            case .yearly: return "¥28.00"
            case .permanent: return "¥68.00"
            }
        }

        var discount: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "-65%"
            case .permanent: return "-50%"
            }
        }

        var discountColor: Color {
            switch self {
            case .yearly: return .blue
            case .permanent: return Color(red: 1.0, green: 0.85, blue: 0.2)
            default: return .clear
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    benefitsCard
                    planSelectionSection
                    mainButton
                    bottomLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .alert("购买成功", isPresented: $showSuccessAlert) {
            Button("确定") { dismiss() }
        } message: {
            Text("您已成功开通会员！")
        }
        .alert("恢复成功", isPresented: $showRestoreSuccessAlert) {
            Button("确定") { dismiss() }
        } message: {
            Text("已成功恢复您的会员资格！")
        }
        .alert("购买失败", isPresented: $vipManager.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(vipManager.purchaseError ?? "未知错误")
        }
        .onChange(of: vipManager.purchaseSuccess) { purchaseSuccess in
            if purchaseSuccess { showSuccessAlert = true }
        }
        .onChange(of: vipManager.restoreSuccess) { restoreSuccess in
            if restoreSuccess { showRestoreSuccessAlert = true }
        }
        .sheet(item: $activeDocument) { document in
            PolicyDocumentView(document: document)
        }
    }

    // MARK: - 头部区域
    private var headerSection: some View {
        HStack {
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 会员特权卡片
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.2))

                Text("会员特权")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 14) {
                benefitRow("更多导出次数", subtitle: "月度30张/日 · 年度100张/日 · 永久不限张数")
                benefitRow("HDR 支持", subtitle: "保留高动态范围色彩信息")
                benefitRow("所有视频时长", subtitle: "不限时长自由选择")
                benefitRow("持续功能更新", subtitle: "解锁更多精彩内容")
                benefitRow("自动同步", subtitle: "与 App Store 账号同步")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func benefitRow(_ title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
    }

    // MARK: - 选择方案
    private var planSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择方案")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                ForEach(PlanType.allCases, id: \.self) { plan in
                    PlanCard(
                        plan: plan,
                        isSelected: selectedPlan == plan
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedPlan = plan
                        }
                    }
                }
            }
        }
    }

    // MARK: - 主按钮
    private var mainButton: some View {
        Button(action: {
            Task {
                switch selectedPlan {
                case .monthly:
                    await vipManager.purchaseMonthly()
               case .yearly:
                    await vipManager.purchaseYearly()
               case .permanent:
                    await vipManager.purchasePermanent()
                }
            }
        }) {
            HStack(spacing: 10) {
                if vipManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 16, weight: .semibold))

                    Text(buttonTitle)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.6, green: 0.2, blue: 0.8),
                        Color(red: 0.9, green: 0.3, blue: 0.6)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.purple.opacity(0.4), radius: 12, y: 6)
        }
        .disabled(vipManager.isLoading)
    }

    private var buttonTitle: String {
        switch selectedPlan {
        case .monthly:
            return "每月 ¥6 解锁"
        case .yearly:
            return "每年 ¥28 解锁"
        case .permanent:
            return "¥68 终身解锁"
        }
    }

    // MARK: - 底部链接
    private var bottomLinks: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                bottomLinkButton("恢复购买") {
                    Task { await vipManager.restorePurchases() }
                }

                linkDivider

                bottomLinkButton("隐私政策") {
                    activeDocument = .privacy
                }

                linkDivider

                bottomLinkButton("使用条款") {
                    activeDocument = .terms
                }
            }

            Text("点击解锁按钮即表示同意《用户协议》。\n付款将从您的 Apple ID 账户中扣除。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private var linkDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 14)
    }

    private func bottomLinkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 方案卡片
struct PlanCard: View {
    let plan: VIPMembershipView.PlanType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 8) {
                    Color.clear.frame(height: 10)

                    Text(plan.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))

                    Text(plan.price)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.purple : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )

                if let discount = plan.discount {
                    VStack(spacing: 0) {
                        Text(discount)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(plan.discountColor)
                            .clipShape(Capsule())
                            .offset(y: -9)

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSelected
                            ? Color.purple.opacity(0.25)
                            : Color.white.opacity(0.05)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 政策文档
private enum PolicyDocument: String, Identifiable {
    case terms, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "使用条款"
        case .privacy: return "隐私政策"
        }
    }

    var content: String {
        switch self {
        case .terms:
            return """
            1. 本应用提供本地视频抽帧与图片导出功能。

            2. 月度会员为订阅制，每月自动续费，可随时取消。

            3. 永久会员为一次性买断，终身使用。

            4. 若您更换设备或重新安装应用，可使用「恢复购买」恢复会员权益。
            """
        case .privacy:
            return """
            1. 本应用不会将您的视频、截图图片或会员数据上传到开发者服务器。

            2. 视频处理、抽帧与图片导出均在本地设备上完成。

            3. 应用仅在选择视频时使用系统照片选择器，导出图片到相册时请求写入权限。
            """
        }
    }
}

private struct PolicyDocumentView: View {
    let document: PolicyDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    Text(document.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                        .lineSpacing(6)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
