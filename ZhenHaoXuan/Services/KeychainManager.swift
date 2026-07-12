import Foundation
import Security

/// 安全的 Keychain 存储管理器。
///
/// 通俗解释：这是 App 的"加密保险柜"。
/// UserDefaults 就像把密码写在便利贴上贴屏幕背面——谁拿到手机都能看。
/// Keychain 则把数据存进 iPhone 硬件安全芯片加密区，即使越狱也很难破解。
///
/// 使用方式：
/// - VIP 状态、购买收据、订阅到期日 → 存 Keychain（防篡改）
/// - UI 偏好（导出格式、主题颜色） → 仍用 UserDefaults（没必要加密）
enum KeychainManager {
    private static let service = "com.zhenhaoxuan.keychain"

    // MARK: - 错误类型

    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .duplicateItem: return "Keychain 条目重复"
            case .itemNotFound: return "Keychain 未找到对应条目"
            case .unexpectedStatus(let status): return "Keychain 操作异常 (状态码: \(status))"
            case .encodingFailed: return "数据编码失败"
            }
        }
    }

    // MARK: - 读取

    static func read(key: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.itemNotFound
        }
        return data
    }

    static func readString(key: String) throws -> String {
        let data = try read(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    static func readBool(key: String) -> Bool {
        (try? read(key: key)).flatMap { data in
            String(data: data, encoding: .utf8).flatMap { Bool($0) }
        } ?? false
    }

    static func readDate(key: String) -> Date? {
        guard let data = try? read(key: key),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    static func readData(key: String) -> Data? {
        try? read(key: key)
    }

    // MARK: - 写入

    static func write(key: String, data: Data) throws {
        // 先尝试删除旧条目（Keychain 不允许直接覆盖）
        try? delete(key: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func writeString(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try write(key: key, data: data)
    }

    static func writeBool(key: String, value: Bool) {
        try? writeString(key: key, value: String(value))
    }

    static func writeDate(key: String, value: Date) {
        let string = ISO8601DateFormatter().string(from: value)
        try? writeString(key: key, value: string)
    }

    // MARK: - 删除

    static func delete(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - 批量操作

    /// 清空本 App 在 Keychain 中的所有数据（用户注销时调用）
    static func clearAll() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
