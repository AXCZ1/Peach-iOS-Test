import Foundation

private struct CompiledRegex: @unchecked Sendable {
    let raw: NSRegularExpression
    init(_ pattern: String) {
        self.raw = try! NSRegularExpression(pattern: pattern)
    }
    func matches(in text: String, range: NSRange) -> [NSTextCheckingResult] {
        raw.matches(in: text, range: range)
    }
    func firstMatch(in text: String, range: NSRange) -> NSTextCheckingResult? {
        raw.firstMatch(in: text, range: range)
    }
    func stringByReplacingMatches(in text: String, range: NSRange, withTemplate: String) -> String {
        raw.stringByReplacingMatches(in: text, range: range, withTemplate: withTemplate)
    }
}

/// Redacts credentials, session cookies, auth tokens, and signed URL parameters
/// before any runtime log entry is written to disk or uploaded.
enum PeachLogRedactor {
    private static let sensitiveParamKeys: Set<String> = [
        "ticket", "t", "token", "access_token", "refresh_token", "id_token",
        "auth", "sig", "signature", "sign", "x-amz-signature", "x-amz-credential",
        "x-amz-security-token", "password", "passwd", "pwd", "cookie", "set-cookie",
        "secret", "key", "session", "peach_session", "tok", "x-token", "x_token",
        "x-auth-token", "x-peach-token", "authorization", "proxy-authorization",
        "passphrase"
    ]

    private static let sensitiveFieldKeyRegex = CompiledRegex(
        "(?i)^(ticket|token|access_token|refresh_token|id_token|password|passwd|pwd|cookie|set-cookie|secret|session|peach_session|authorization|proxy-authorization|x[-_]token|x[-_]auth[-_]token|x[-_]peach[-_]token|passphrase|tok|sig|signature|x-amz-signature|x-amz-credential|x-amz-security-token|auth)$"
    )

    private static let embeddedURLRegex = CompiledRegex(
        "https?://[^\\s\"'<>()\\[\\]{}]+"
    )

    private static let userinfoRegex = CompiledRegex(
        "(https?://[^/\\s:@]+:)([^@\\s/]+)(@)"
    )

    private static let inlineAuthHeaderRegex = CompiledRegex(
        "(?i)\\b(authorization|proxy-authorization|x-token|x-auth-token|x-peach-token)\\s*:\\s*(?:(?:Bearer|Basic)\\s+[^\\s\"',;]+|[^\\s\"',;\\r\\n]+)"
    )

    private static let inlineCookieHeaderRegex = CompiledRegex(
        "(?i)\\b(cookie|set-cookie)\\s*:\\s*(?:[^\\s,;]+=[^\\s,;\\r\\n]+(?:\\s*;\\s*[^\\s,;]+=[^\\s,;\\r\\n]+)*)"
    )

    private static let bearerBasicRegex = CompiledRegex(
        "(?i)\\b(Bearer|Basic)\\s+([A-Za-z0-9._~+/=-]+)"
    )

    private static let queryPairRegex = CompiledRegex(
        "(?i)([?&;])(ticket|t|token|access_token|refresh_token|id_token|auth|sig|signature|sign|x-amz-signature|x-amz-credential|x-amz-security-token|password|passwd|pwd|cookie|set-cookie|secret|key|session|peach_session|tok|x-token|x_token|x-auth-token|x-peach-token|passphrase)=([^&\\s#\"'<>]+)"
    )

    private static let pctQueryPairRegex = CompiledRegex(
        "(?i)(%3[fF]|%26)(ticket|t|token|access_token|refresh_token|id_token|auth|sig|signature|sign|password|passwd|pwd|cookie|secret|key|session|peach_session|tok|passphrase)%3[dD]([^%&\\s\"'<>]+(?:%[0-9a-fA-F]{2}[^%&\\s\"'<>]*)*)"
    )

    private static let assignSecretRegex = CompiledRegex(
        "(?i)(?:(?<=^)|(?<=[\\s?&;,(\"'\\[{]))(ticket|token|access_token|refresh_token|id_token|password|passwd|pwd|cookie|set-cookie|secret|session|peach_session|authorization|proxy-authorization|x[-_]token|x[-_]auth[-_]token|x[-_]peach[-_]token|passphrase|tok|sig|signature|x-amz-signature|x-amz-credential|x-amz-security-token)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|(?:\\[REDACTED\\]|[^\\s\"'&;,#<>]+))"
    )

    private static let jsonKVSecretRegex = CompiledRegex(
        "(?i)(\"(?:password|passwd|pwd|cookie|set-cookie|token|access_token|refresh_token|id_token|x_token|x-token|x-auth-token|x-peach-token|ticket|secret|session|peach_session|authorization|proxy-authorization|passphrase|tok|sig|signature|auth)\"\\s*:\\s*\")([^\"]*)(\")"
    )

    static func redactText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = replaceURLs(in: text)
        out = replace(out, regex: userinfoRegex, template: "$1[REDACTED]$3")
        out = replaceGroup1Header(out, regex: inlineAuthHeaderRegex)
        out = replaceGroup1Header(out, regex: inlineCookieHeaderRegex)
        out = replace(out, regex: bearerBasicRegex, template: "$1 [REDACTED]")
        out = replace(out, regex: queryPairRegex, template: "$1$2=[REDACTED]")
        out = replace(out, regex: pctQueryPairRegex, template: "$1$2%3D%5BREDACTED%5D")
        out = replaceGroup1Assignment(out, regex: assignSecretRegex)
        out = replace(out, regex: jsonKVSecretRegex, template: "$1[REDACTED]$3")
        return out
    }

    static func redactFields(_ fields: [String: String]) -> [String: String] {
        guard !fields.isEmpty else { return [:] }
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(fields.count)
        for (key, value) in fields {
            if isSensitiveKey(key) {
                redacted[key] = "[REDACTED]"
            } else {
                redacted[key] = redactText(value)
            }
        }
        return redacted
    }

    static func isSensitiveKey(_ key: String) -> Bool {
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        return sensitiveFieldKeyRegex.firstMatch(in: key, range: range) != nil
    }

    private static func replaceURLs(in text: String) -> String {
        let nsText = text as NSString
        let matches = embeddedURLRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let rawURL = nsText.substring(with: match.range)
            mutable.replaceCharacters(in: match.range, with: redactSingleURL(rawURL))
        }
        return mutable as String
    }

    private static func redactSingleURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        if components.password != nil {
            components.password = "[REDACTED]"
        }
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { item in
                let lower = item.name.lowercased()
                if sensitiveParamKeys.contains(lower) {
                    return URLQueryItem(name: item.name, value: "[REDACTED]")
                }
                if let val = item.value, val.contains("://") {
                    return URLQueryItem(name: item.name, value: redactText(val))
                }
                return item
            }
        }
        guard let rebuilt = components.string else { return raw }
        return rebuilt
            .replacingOccurrences(of: "=%5BREDACTED%5D", with: "=[REDACTED]")
            .replacingOccurrences(of: ":%5BREDACTED%5D@", with: ":[REDACTED]@")
    }

    private static func replace(_ text: String, regex: CompiledRegex, template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replaceGroup1Header(_ text: String, regex: CompiledRegex) -> String {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() where match.numberOfRanges >= 2 {
            let key = nsText.substring(with: match.range(at: 1))
            mutable.replaceCharacters(in: match.range, with: "\(key): [REDACTED]")
        }
        return mutable as String
    }

    private static func replaceGroup1Assignment(_ text: String, regex: CompiledRegex) -> String {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() where match.numberOfRanges >= 2 {
            let key = nsText.substring(with: match.range(at: 1))
            mutable.replaceCharacters(in: match.range, with: "\(key)=[REDACTED]")
        }
        return mutable as String
    }
}
