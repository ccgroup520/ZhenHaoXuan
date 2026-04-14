import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @ObservedObject private var exportSettings = ExportSettings.shared
    @ObservedObject private var vipManager = VIPManager.shared
    @ObservedObject private var userProfile = UserProfileManager.shared

    @State private var showVIPView = false
    @State private var showSignIn = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    profileSection

                    if !vipManager.isPaidUser {
                        membershipPromoCard
                    }

                    exportSettingsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVIPView) {
            VIPMembershipView()
        }
        .sheet(isPresented: $showSignIn) {
            AppleSignInView()
        }
        .alert("购买失败", isPresented: $vipManager.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(vipManager.purchaseError ?? "未知错误")
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var profileSection: some View {
        Button(action: {
            if !userProfile.isSignedIn {
                showSignIn = true
            }
        }) {
            VStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = userProfile.userImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppPalette.brandSky, AppPalette.brandBlue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                    .shadow(color: AppPalette.brandBlue.opacity(0.3), radius: 16, y: 8)

                    if vipManager.isPaidUser {
                        Image(systemName: "crown.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(AppPalette.brandOrangeDeep, in: Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }

                Text(userProfile.isSignedIn ? userProfile.userName : "点击登录")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .padding(24)
        .withPageAnimation()
    }

    private var membershipPromoCard: some View {
        Button(action: {
            showVIPView = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppPalette.brandOrange, AppPalette.brandOrangeDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "crown.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("升级会员")
                        .font(.headline)

                    Text("无限导出 · 无限时长 · HDR支持")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppPalette.brandOrange.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        }
        .buttonStyle(AppPressableButtonStyle())
        .withPageAnimation(delay: 0.1)
    }

    private var exportSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("导出设置")
                    .font(.headline)

                Spacer()

                AppPill(
                    title: exportSettings.quality.displayName,
                    systemImage: "sparkles",
                    color: AppPalette.brandBlueDeep
                )
            }

            Picker("图片格式", selection: $exportSettings.format) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            Toggle(isOn: $exportSettings.hdrEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("保留 HDR 信息")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        if !vipManager.canUseHDR {
                            AppPill(
                                title: "会员",
                                systemImage: "crown.fill",
                                color: AppPalette.brandOrange
                            )
                        }
                    }

                    Text(vipManager.canUseHDR ? "保存高动态范围颜色信息" : "升级会员解锁HDR导出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AppPalette.brandBlue)
            .disabled(!vipManager.canUseHDR)
            .onChange(of: exportSettings.hdrEnabled) { newValue in
                if newValue && !vipManager.canUseHDR {
                    exportSettings.hdrEnabled = false
                    showVIPView = true
                }
            }

            Divider()

            ForEach(ExportQuality.allCases, id: \.self) { quality in
                Button(action: {
                    exportSettings.quality = quality
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(qualityHint(for: quality))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: exportSettings.quality == quality ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(exportSettings.quality == quality ? AppPalette.brandBlue : Color.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(exportSettings.quality == quality ? AppPalette.brandBlue.opacity(0.10) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
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
        .withPageAnimation(delay: 0.2)
    }

    private func qualityHint(for quality: ExportQuality) -> String {
        switch quality {
        case .lossless: return "适合后期编辑"
        case .high: return "推荐日常使用"
        case .medium: return "快速分享"
        case .low: return "临时保存"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

struct AppleSignInView: View {
    @Environment(\.dismiss) private var dismiss

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppPalette.brandBlue, AppPalette.brandBlueDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "apple.logo")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 8) {
                        Text("登录账户")
                            .font(.title2.weight(.bold))

                        Text(isSimulator ? "模拟器环境，可体验登录流程" : "使用 Apple 账户登录，同步会员状态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if isSimulator {
                        Button(action: { simulateLogin() }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("模拟登录")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [AppPalette.brandOrange, AppPalette.brandOrangeDeep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .buttonStyle(AppPressableButtonStyle())
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName]
                        } onCompletion: { result in
                            UserProfileManager.shared.handleAppleSignIn(result: result)
                            dismiss()
                        }
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Button("暂不登录") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func simulateLogin() {
        let names = ["张三", "李四", "王五", "赵六", "测试用户"]
        let randomName = names.randomElement() ?? "测试用户"

        UserProfileManager.shared.saveUserProfile(
            name: randomName,
            image: UserProfileManager.shared.createDefaultAvatar(name: randomName)
        )

        dismiss()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
