import Foundation

/// Debug-only, non-persistent launch fixtures. They never replace a saved vault.
enum NotoPreviewConfiguration {
    static var vaultPath: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTO_PREVIEW_VAULT"] ?? argument("-notoPreviewVaultPath")
        #else
        nil
        #endif
    }
    static var isEnabled: Bool { vaultPath != nil }
    static var windowWidth: Double? {
        #if DEBUG
        (ProcessInfo.processInfo.environment["NOTO_PREVIEW_WINDOW_WIDTH"] ?? argument("-notoPreviewWindowWidth")).flatMap(Double.init)
        #else
        nil
        #endif
    }
    static var windowHeight: Double? {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTO_PREVIEW_WINDOW_HEIGHT"].flatMap(Double.init)
        #else
        nil
        #endif
    }
    private static func argument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
