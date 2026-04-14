//
//  VIPManager.swift
//  ZhenHaoXuan
//
//  VIP会员管理器 - 三级会员体系：普通用户/月度会员/永久会员
//

import Foundation
import StoreKit
import Combine

enum VIPTier: String, CaseIterable {
    case free = "free"
    case monthly = "monthly"
    case permanent = "permanent"
    
    var displayName: String {
        switch self {
        case .free: return "普通用户"
        case .monthly: return "月度会员"
        case .permanent: return "永久会员"
        }
    }
    
    var isPaid: Bool {
        self != .free
    }
}

class VIPManager: ObservableObject {
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
    private let permanentProductID = "com.zhenhaoxuan.vip.permanent"
    
    // MARK: - UserDefaults Keys
    private let vipTierKey = "vipTier"
    private let vipPurchaseDateKey = "vipPurchaseDate"
    private let subscriptionExpiryKey = "subscriptionExpiryDate"
    private let dailyExportCountKey = "dailyExportCount"
    private let lastExportDateKey = "lastExportDate"
    
    // MARK: - Constants
    private let dailyFreeLimit = 3
    private let dailyMonthlyLimit = 50
    private let freeVideoDurationLimit: TimeInterval = 30
    
    // MARK: - StoreKit Products
    @Published var monthlyProduct: Product?
    @Published var permanentProduct: Product?
    private var updateListenerTask: Task<Void, Error>?
    
    // MARK: - Initialization
    private init() {
        #if DEBUG
        // 测试阶段：自动设置为永久会员（注释掉以测试非会员界面）
        // UserDefaults.standard.set(VIPTier.permanent.rawValue, forKey: vipTierKey)
        // UserDefaults.standard.set(Date(), forKey: vipPurchaseDateKey)
        #endif
        
        loadVIPStatus()
        startListeningForTransactions()
        
        Task {
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
        UserDefaults.standard.object(forKey: vipPurchaseDateKey) as? Date
    }
    
    // MARK: - Daily Export Limit
    
    var todayExportCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastExportDate = UserDefaults.standard.object(forKey: lastExportDateKey) as? Date,
           calendar.isDate(lastExportDate, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: dailyExportCountKey)
        } else {
            UserDefaults.standard.set(0, forKey: dailyExportCountKey)
            UserDefaults.standard.set(today, forKey: lastExportDateKey)
            return 0
        }
    }
    
    var canExport: Bool {
        remainingExports > 0
    }
    
    var remainingExports: Int {
        switch currentTier {
        case .free:
            return max(0, dailyFreeLimit - todayExportCount)
        case .monthly:
            // 检查订阅是否过期
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                // 订阅已过期，降级为免费用户
                return max(0, dailyFreeLimit - todayExportCount)
            }
            return max(0, dailyMonthlyLimit - todayExportCount)
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
        case .permanent:
            return "无限次"
        }
    }
    
    // MARK: - Video Duration Limit
    
    var maxVideoDuration: TimeInterval {
        switch currentTier {
        case .free:
            return freeVideoDurationLimit
        case .monthly, .permanent:
            return .greatestFiniteMagnitude
        }
    }
    
    var videoDurationLimitDescription: String {
        switch currentTier {
        case .free:
            return "30秒以内"
        case .monthly, .permanent:
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
        false // 所有用户都没有水印
    }
    
    var supportsBatchExport: Bool {
        true // 所有用户都支持批量导出
    }
    
    // MARK: - Private Methods
    
    private func loadVIPStatus() {
        if let tierString = UserDefaults.standard.string(forKey: vipTierKey),
           let tier = VIPTier(rawValue: tierString) {
            currentTier = tier
        }
        subscriptionExpiryDate = UserDefaults.standard.object(forKey: subscriptionExpiryKey) as? Date
    }
    
    @MainActor
    private func saveVIPStatus(tier: VIPTier, expiryDate: Date? = nil) {
        UserDefaults.standard.set(tier.rawValue, forKey: vipTierKey)
        UserDefaults.standard.set(Date(), forKey: vipPurchaseDateKey)
        if let expiry = expiryDate {
            UserDefaults.standard.set(expiry, forKey: subscriptionExpiryKey)
            subscriptionExpiryDate = expiry
        }
        currentTier = tier
    }
    
    func checkSubscriptionStatus() {
        // 检查月度会员是否过期
        if currentTier == .monthly {
            if let expiry = subscriptionExpiryDate, expiry < Date() {
                // 订阅已过期，降级为免费用户
                UserDefaults.standard.set(VIPTier.free.rawValue, forKey: vipTierKey)
                currentTier = .free
                objectWillChange.send()
            }
        }
    }
    
    func resetDailyExportCount() {
        UserDefaults.standard.set(0, forKey: dailyExportCountKey)
        UserDefaults.standard.set(Date(), forKey: lastExportDateKey)
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
    
    @MainActor
    func requestProducts() async {
        purchaseError = nil
        showError = false
        isProductsLoaded = false
        
        do {
            let productIDs = [monthlyProductID, permanentProductID]
            let products = try await Product.products(for: productIDs)
            
            for product in products {
                switch product.id {
                case monthlyProductID:
                    self.monthlyProduct = product
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
    
    @MainActor
    func purchaseMonthly() async {
        await purchase(product: monthlyProduct)
    }
    
    @MainActor
    func purchasePermanent() async {
        await purchase(product: permanentProduct)
    }
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
    private func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .unverified(_, _):
            showError(message: "购买验证失败，请稍后重试")
            
        case .verified(let transaction):
            switch transaction.productID {
            case monthlyProductID:
                // 月度会员，设置30天后过期
                let expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                saveVIPStatus(tier: .monthly, expiryDate: expiryDate)
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
    
    @MainActor
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
                    // 恢复月度会员，检查是否过期
                    let expiryDate = transaction.expirationDate
                    if let expiry = expiryDate, expiry > Date() {
                        saveVIPStatus(tier: .monthly, expiryDate: expiry)
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
    
    // MARK: - Export Recording
    
    @MainActor
    func recordExport(count: Int = 1) {
        guard count > 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var currentCount = 0
        if let lastExportDate = UserDefaults.standard.object(forKey: lastExportDateKey) as? Date,
           calendar.isDate(lastExportDate, inSameDayAs: today) {
            currentCount = UserDefaults.standard.integer(forKey: dailyExportCountKey)
        }
        
        currentCount += count
        UserDefaults.standard.set(currentCount, forKey: dailyExportCountKey)
        UserDefaults.standard.set(today, forKey: lastExportDateKey)
        objectWillChange.send()
    }

    @MainActor
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
