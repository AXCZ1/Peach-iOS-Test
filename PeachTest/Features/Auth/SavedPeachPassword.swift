import Foundation
import Security

enum SavedPeachPassword {
    private static func query(_ origin: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.axcz1.peachios.test.password",
         kSecAttrAccount as String: origin.absoluteString]
    }

    static func read(for origin: URL) throws -> String? {
        var lookup = query(origin)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ password: String, for origin: URL) throws {
        let data = Data(password.utf8)
        let existing = query(origin)
        let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { try check(status); return }
        var new = existing
        new[kSecValueData as String] = data
        new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(new as CFDictionary, nil))
    }

    static func remove(for origin: URL) throws {
        let status = SecItemDelete(query(origin) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw PeachAPIError(message: "系统钥匙串不可用（\(status)）") }
    }
}
