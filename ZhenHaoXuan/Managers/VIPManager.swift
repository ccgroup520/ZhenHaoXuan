//
//  VIPManager.swift
//  ZhenHaoXuan
//
//  VIP会员管理器 - 三级会员体系：普通用户/月度会员/永久会员
//
//  安全策略：
//  - 会员等级、到期日、购买收据 → Keychain 加密存储（防篡改）
//  - 每日导出计数 → UserDefaults（非敏感，丢了也就多导出一张）
//  - App 启动时向 Apple 验证收据真伪
//  - 导出配额采用"预扣-确认-释放"模式，防止并发超限
//

import Foundation
import StoreKit
import Combine

enum VIPTier: String, CaseIterable {
    case free = "free"
    case monthly = "monthly"
    case yearly = "yearly"
    case permanent = "permanent"

    var displayName: String {
        switch self {
        case .free: return "普通用户"
        case .monthly: return "月度会员"
        case .yearly: return "年度会员"
        case .permanent: return "永久会员"
        }
    }

    var isPaid: Bool {
        self != .free
    }
}

@MainActor
final class VIPManager: ObservableObject {
    static let shared = VIPManager()

    // MARK: - Published Properties
    @Published var currentTier: VIPTier = .free
    @Published var subscriptionExpiryDate: Date?
    @Published var isLoading = false
    @Published var purchaseError: String?
    @Published var showError = false
    @Published var purchaseSuccess = false
    @Published var restoreSuccess = false
    @Published var isProductsLoaded = false

    // MARK: - Product IDs
    private let monthlyProductID = "com.zhenhaoxuan.vip.monthly"
    private let yearlyProductID = "com.zhenhaoxuan.vip.yearly"
    private let permanentProductID = "com.zhenhaoxuan.vip.permanent"

    // MARK: - Keychain Keys（敏感数据放 Keychain 加密保险柜）
    private enum KeychainKey {
        static let vipTier = "vipTier"
        static let purchaseDate = "vipPurchaseDate"
        static let subscriptionExpiry = "subscriptionExpiryDate"
        static let appStoreReceiptHash = "appStoreReceiptHash"
    }

    // MARK: - UserDefaults Keys（仅放非敏感数据）
    private enum UDKey {
        static let dailyExportCount = "dailyExportCount"
        static let lastExportDate = "lastExportDate"
    }

    // MARK: - Constants
    private let dailyFreeLimit = 3
    private let dailyMonthlyLimit = 50
    private let freeVideoDurationLimit: TimeInterval = 30

    // MARK: - StoreKit Products
    @Published var monthlyProduct: Product?
    @Published var yearlyProduct: Product?
    @Published var permanentProduct: Product?
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - 导出额度预扣（防止并发超限）
    private var reservedQuota: Int = 0

    // MARK: - Initialization
    private init() {
        #if DEBUG
        // 测试阶段：自动设置为永久会员（注释掉以测试非会员界面）
        // KeychainManager.writeString(key: KeychainKey.vipTier, value: VIPTier.permanent.rawValue)
        // KeychainManager.writeDate(key: KeychainKey.purchaseDate, value: Date())
        #endif

        loadVIPStatus()
        startListeningForTransactions()

        Task {
            // 启动时用 StoreKit 2 校验会员真伪 + 请求商品
            await syncEntitlements()
            await requestProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - VIP Status

    var isPaidUser: Bool {
        currentTier.isPaid
    }

    var purchaseDate: Date? {
        KeychainManager.readDate(key: KeychainKey.purchaseDate)
    }

    // MARK: - 会员校验（StoreKit 2）

    /// 启动时用 StoreKit 2 的 currentEntitlements 校验会员真伪。
    ///
    /// 为什么不再用旧的 appStoreReceiptURL：
    /// - StoreKit 2 的交易已由 Apple 签名，本地即可验证，且离线可用
    /// - 旧 appStoreReceiptURL 在 StoreKit 2 应用中往往不存在，依赖它会把付费用户误判为免费
    ///
    /// 只有在确实找不到任何有效购买时才降级，避免误伤付费用户。
    private func syncEntitlements() async {
        var hasPermanent = false
        var activeTier: VIPTier?
        var activeExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // 已退款/已撤销的交易不计入
            if transaction.revocationDate != nil { continue }

            switch transaction.productID {
            case permanentProductID:
                hasPermanent = true

            case monthlyProductID, yearlyProductID:
                guard let expiry = transaction.expirationDate, expiry > Date() else { continue }
                if activeExpiry == nil || expiry > activeExpiry! {
                    activeExpiry = expiry
                    activeTier = (transaction.productID == yearlyProductID) ? .yearly : .monthly
                }

            default:
                break
            }
        }

        if hasPermanent {
            saveVIPStatus(tier: .permanent)
        } else if let tier = activeTier, let expiry = activeExpiry {
            saveVIPStatus(tier: tier, expiryDate: expiry)
        } else {
            // 确实无任何有效购买 → 降级为免费
            resetToFree()
        }
    }

    private func resetToFree() {
        currentTier = .free
        subscriptionExpiryDate = nil
        try? KeychainManager.writeString(key: KeychainKey.vipTier, value: VIPTier.free.rawValue)
        try? KeychainManager.delete(key: KeychainKey.subscriptionExpiry)
        objectWillChange.send()
    }

    // MARK: - Daily Export Limit

    var todayExportCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastExportDate = UserDefaults.standard.object(forKey: UDKey.lastExportDate) as? Date,
           calendar.isDate(lastExportDate, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: UDKey.dailyExportCount)
        } else {
            UserDefaults.standard.set(0, forKey: UDKey.dailyExportCount)
            UserDefaults.standard.set(today, forKey: UDKey.lastExportDate)
            return 0
        }
    }

    var canExport: Bool {
        remainingExports > 0
    }

    var remainingExports: Int {
        switch currentTier {
        case .free:
            return max(0, dailyFreeLimit - todayExportCount - reservedQuota)
        case .monthly:
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                return max(0, dailyFreeLimit - todayExportCount - reservedQuota)
            }
           return max(0, dailyMonthlyLimit - todayExportCount - reservedQuota)
        case .yearly:
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                return max(0, dailyFreeLimit - todayExportCount - reservedQuota)
            }
            return max(0, dailyMonthlyLimit - todayExportCount - reservedQuota)
       case .permanent:
            return Int.max
        }
    }

    var exportLimitDescription: String {
        switch currentTier {
        case .free:
            return "每日3次"
        case .monthly:
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                return "订阅已过期，每日3次"
            }
           return "每日50次"
        case .yearly:
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                return "订阅已过期，每日3次"
            }
            return "每日50次"
       case .permanent:
            return "无限次"
        }
    }

    // MARK: - 导出额度预扣（防并发超限）

    /// 预扣 N 张导出配额。返回 true 表示额度够，返回 false 表示不够。
    /// 成功预扣后必须调用 confirmExport 或 releaseExportQuota 之一。
    func reserveExportQuota(count: Int) -> Bool {
        guard count > 0 else { return true }
        guard currentTier != .permanent else { return true } // 永久会员不限制

        let available = remainingExports
        guard available >= count else { return false }

        reservedQuota += count
        return true
    }

    /// 确认扣款（导出成功时调用）
    func confirmExport(count: Int) {
        reservedQuota = max(0, reservedQuota - count)
        actuallyRecordExport(count: count)
    }

    /// 释放预扣额度（导出失败时调用）
    func releaseExportQuota(count: Int) {
        reservedQuota = max(0, reservedQuota - count)
        objectWillChange.send()
    }

    /// 实际写入 UserDefaults（仅内部调用）
    private func actuallyRecordExport(count: Int) {
        guard count > 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var currentCount = 0
        if let lastExportDate = UserDefaults.standard.object(forKey: UDKey.lastExportDate) as? Date,
           calendar.isDate(lastExportDate, inSameDayAs: today) {
            currentCount = UserDefaults.standard.integer(forKey: UDKey.dailyExportCount)
        }

        currentCount += count
        UserDefaults.standard.set(currentCount, forKey: UDKey.dailyExportCount)
        UserDefaults.standard.set(today, forKey: UDKey.lastExportDate)
        objectWillChange.send()
    }

    /// 兼容旧接口：直接记录导出（用于不需要预扣的简单场景）
    func recordExport(count: Int = 1) {
        confirmExport(count: count)
    }

    // MARK: - Video Duration Limit

    var maxVideoDuration: TimeInterval {
        switch currentTier {
        case .free:
            return freeVideoDurationLimit
        case .monthly, .yearly, .permanent:
            return .greatestFiniteMagnitude
        }
    }

    var videoDurationLimitDescription: String {
        switch currentTier {
        case .free:
            return "30秒以内"
        case .monthly, .yearly, .permanent:
            return "无限制"
        }
    }

    func canSelectVideo(duration: TimeInterval) -> Bool {
        duration <= maxVideoDuration
    }

    // MARK: - HDR Support

    var canUseHDR: Bool {
        currentTier != .free
    }

    // MARK: - Quality (All users get best quality)

    var hasWatermark: Bool {
        false
    }

    var supportsBatchExport: Bool {
        true
    }

    // MARK: - Private Methods

    private func loadVIPStatus() {
        if let tierString = try? KeychainManager.readString(key: KeychainKey.vipTier),
           let tier = VIPTier(rawValue: tierString) {
            currentTier = tier
        }
        subscriptionExpiryDate = KeychainManager.readDate(key: KeychainKey.subscriptionExpiry)
    }

    private func saveVIPStatus(tier: VIPTier, expiryDate: Date? = nil) {
        try? KeychainManager.writeString(key: KeychainKey.vipTier, value: tier.rawValue)
        KeychainManager.writeDate(key: KeychainKey.purchaseDate, value: Date())
        if let expiry = expiryDate {
            KeychainManager.writeDate(key: KeychainKey.subscriptionExpiry, value: expiry)
            subscriptionExpiryDate = expiry
        } else {
            try? KeychainManager.delete(key: KeychainKey.subscriptionExpiry)
            subscriptionExpiryDate = nil
        }
        currentTier = tier
    }

   func checkSubscriptionStatus() {
        if currentTier == .monthly || currentTier == .yearly {
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                try? KeychainManager.writeString(key: KeychainKey.vipTier, value: VIPTier.free.rawValue)
                currentTier = .free
                objectWillChange.send()
            }
        }
    }

    func resetDailyExportCount() {
        UserDefaults.standard.set(0, forKey: UDKey.dailyExportCount)
        UserDefaults.standard.set(Date(), forKey: UDKey.lastExportDate)
    }

    // MARK: - StoreKit Integration

    private func startListeningForTransactions() {
        updateListenerTask = Task { [weak self] in
            guard let self = self else { return }
            for await result in Transaction.updates {
                await self.handleTransactionResult(result)
            }
        }
    }

    func requestProducts() async {
        purchaseError = nil
        showError = false
        isProductsLoaded = false

        do {
            let productIDs = [monthlyProductID, yearlyProductID, permanentProductID]
            let products = try await Product.products(for: productIDs)

            for product in products {
                switch product.id {
                case monthlyProductID:
                    self.monthlyProduct = product
                case yearlyProductID:
                    self.yearlyProduct = product
                case permanentProductID:
                    self.permanentProduct = product
                default:
                    break
                }
            }

            self.isProductsLoaded = !products.isEmpty
        } catch {
            debugLog("获取产品失败: \(error.localizedDescription)")
            self.isProductsLoaded = false
        }
    }

    // MARK: - Purchase

    func purchaseMonthly() async {
        await purchase(product: monthlyProduct)
    }

   func purchasePermanent() async {
       await purchase(product: permanentProduct)
   }

    func purchaseYearly() async {
        await purchase(product: yearlyProduct)
    }

   private func purchase(product: Product?) async {
        purchaseError = nil
        showError = false
        purchaseSuccess = false
        restoreSuccess = false

        if product == nil {
            await requestProducts()
        }

        guard let product = product else {
            showError(message: "无法获取商品信息，请检查网络连接后重试")
            return
        }

        await performPurchase(product: product)
    }

    private func performPurchase(product: Product) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                await handleTransactionResult(verification)

            case .userCancelled:
                break

            case .pending:
                showError(message: "购买正在处理中，请稍候。完成后会自动更新会员状态。")

            @unknown default:
                showError(message: "购买失败，请稍后重试")
            }
        } catch {
            if let skError = error as? SKError {
                switch skError.code {
                case .paymentCancelled:
                    break
                case .paymentInvalid:
                    showError(message: "支付信息无效，请重试")
                case .paymentNotAllowed:
                    showError(message: "此设备不允许进行内购")
                case .storeProductNotAvailable:
                    showError(message: "产品不可用，请稍后重试")
                case .clientInvalid:
                    showError(message: "用户不允许进行支付")
                default:
                    showError(message: "购买失败: \(skError.localizedDescription)")
                }
            } else {
                showError(message: "购买失败: \(error.localizedDescription)")
            }
        }
    }

    private func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .unverified(_, _):
            showError(message: "购买验证失败，请稍后重试")

        case .verified(let transaction):
            switch transaction.productID {
            case monthlyProductID:
                let expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                saveVIPStatus(tier: .monthly, expiryDate: expiryDate)
                await transaction.finish()
               purchaseSuccess = true

            case yearlyProductID:
                let expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())
                saveVIPStatus(tier: .yearly, expiryDate: expiryDate)
                await transaction.finish()
                purchaseSuccess = true

           case permanentProductID:
                saveVIPStatus(tier: .permanent)
                await transaction.finish()
                purchaseSuccess = true

            default:
                break
            }
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        showError = false
        restoreSuccess = false
        defer { isLoading = false }

        var foundPurchase = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .unverified(_, _):
                break

            case .verified(let transaction):
                switch transaction.productID {
                case monthlyProductID:
                    let expiryDate = transaction.expirationDate
                    if let expiry = expiryDate, expiry > Date() {
                        saveVIPStatus(tier: .monthly, expiryDate: expiry)
                        await transaction.finish()
                        foundPurchase = true
                    }

                case yearlyProductID:
                    let expiryDate = transaction.expirationDate
                    if let expiry = expiryDate, expiry > Date() {
                        saveVIPStatus(tier: .yearly, expiryDate: expiry)
                        await transaction.finish()
                        foundPurchase = true
                    }

                case permanentProductID:
                    saveVIPStatus(tier: .permanent)
                    await transaction.finish()
                    foundPurchase = true

                default:
                    break
                }
            }
        }

        if foundPurchase {
            restoreSuccess = true
        } else {
            showError(message: "未找到购买记录，请确认您已购买过会员")
        }
    }

    // MARK: - Error

    private func showError(message: String) {
        purchaseError = message
        showError = true
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
