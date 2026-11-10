import Foundation
import Security

enum SavedPeachPassword {
    static let peachService = "com.axcz1.peachios.test.password"
    static let seekPreviewService = "com.axcz1.peachios.test.seek-preview-password"

    private static func query(_ origin: URL, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: origin.absoluteString]
    }

    static func read(for origin: URL, service: String = peachService) throws -> String? {
        var lookup = query(origin, service: service)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ password: String, for origin: URL, service: String = peachService) throws {
        let data = Data(password.utf8)
        let existing = query(origin, service: service)
        let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { try check(status); return }
        var new = existing
        new[kSecValueData as String] = data
        new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(new as CFDictionary, nil))
    }

    static func remove(for origin: URL, service: String = peachService) throws {
        let status = SecItemDelete(query(origin, service: service) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw PeachAPIError(message: "系统钥匙串不可用（\(status)）") }
    }
}
