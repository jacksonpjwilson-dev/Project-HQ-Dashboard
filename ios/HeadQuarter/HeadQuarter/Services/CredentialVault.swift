import Foundation
import Security

enum CredentialVault {
    static func read(_ id: UUID) throws -> String? {
        var query = base(id); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw VaultError.status(status) }
        return value
    }
    static func set(_ token: String, for id: UUID) throws {
        let query = base(id)
        if token.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw VaultError.status(result) }; return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw VaultError.status(result) }
        } else if status != errSecSuccess { throw VaultError.status(status) }
    }
    private static func base(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.headquarter.monitoring", kSecAttrAccount as String: id.uuidString]
    }
    enum VaultError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? { "Secure credential storage failed (\(self))." }
    }
}
