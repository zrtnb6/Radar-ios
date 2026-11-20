import Foundation
import Security

/// GitHub 令牌只依赖 Keychain：iOS 上使用 `AfterFirstUnlock`，
/// 这样后台刷新（BGAppRefreshTask）在设备锁屏时也能读到令牌。
enum KeychainService {
    private static let service = "com.releaseradar.ios.github-token"
    private static let account = "fine-grained-pat"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteToken()
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = Data(trimmed.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.saveFailed(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    static func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func hasToken() -> Bool {
        loadToken()?.isEmpty == false
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "无法安全保存 Token（Keychain 错误 \(status)）。"
        }
    }
}
