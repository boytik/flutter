import Foundation
import CryptoKit

/// Строит стабильный ключ для кэша по URL + методу + «vary»-заголовкам.
public struct HTTPCacheKey {
    /// `headers` умышленно non-optional; передаём пустой словарь, если нет заголовков.
    public static func make(url: URL, method: String, headers: [String: String] = [:]) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        if let q = comps.queryItems {
            comps.queryItems = q.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        }
        let normalizedURL = comps.url?.absoluteString ?? url.absoluteString

        let varyHeaders = ["Accept-Language"]
        let filtered = headers
            .filter { varyHeaders.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ";")

        var keyString = method + " " + normalizedURL
        if !filtered.isEmpty { keyString += " HEADERS:" + filtered }

        let digest = SHA256.hash(data: Data(keyString.utf8))
        let b64 = Data(digest).base64EncodedString()
        let base64url = b64
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")

        return base64url
    }
}
