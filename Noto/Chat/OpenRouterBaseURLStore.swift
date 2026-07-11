import Foundation

/// Persists an optional custom OpenRouter API base URL in `UserDefaults`.
///
/// This is the escape hatch for users on networks/regions that block
/// `openrouter.ai` at the edge (e.g. Hong Kong), where AI chat otherwise only
/// works behind a VPN. Point this at a proxy that fronts OpenRouter — a small
/// Cloudflare Worker, for example — that egresses from a non-blocked region, and
/// chat works without a VPN.
///
/// Non-sensitive config (just a URL), so `UserDefaults` is correct here; the API
/// key stays in the Keychain via `OpenRouterKeyStore`.
enum OpenRouterBaseURLStore {
    private static let key = "com.noto.openrouter.baseURL"

    /// The shipped default — OpenRouter's real API root.
    static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    /// The raw saved string (trimmed), or nil if the default is in use.
    static func load() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Save a custom base URL. Empty/blank input clears the override (back to default).
    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// True when a non-default override is in effect.
    static var hasOverride: Bool { resolved() != defaultBaseURL }

    /// The base URL chat should use: a valid saved override, else the default.
    /// Only `http`/`https` absolute URLs are accepted; anything else falls back.
    static func resolved() -> URL {
        guard let raw = load(),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return defaultBaseURL
        }
        return url
    }
}
