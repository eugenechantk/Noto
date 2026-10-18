import AppIntents
import Foundation
import NotoShareCapture
import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "SaveQuickCapture")

/// What "Save Quick Capture" does, separated from the App Intent so it can be tested against a
/// temporary vault: file the text as an `inbox/` capture note — the same filing the Capture tab and
/// share sheet use — or, when the vault can't be reached, stage it for the next launch's drain.
enum QuickCaptureAction {
    struct Outcome: Equatable {
        /// Vault-relative path of the note, when it was filed now.
        var relativePath: String?
        /// Id of the staged capture, when the vault wasn't reachable.
        var stagedID: UUID?
        var title: String
        var body: String
        /// Where tapping the notification goes.
        var link: URL
    }

    enum ActionError: LocalizedError {
        case emptyText, nowhereToSave
        var errorDescription: String? {
            switch self {
            case .emptyText: return "There's no text to save."
            case .nowhereToSave: return "Noto 2 has no vault yet. Open Noto 2 and choose one."
            }
        }
    }

    static func run(text: String, vaultURL: URL?, store: PendingCaptureStore?,
                    makeService: (URL) -> CaptureFilingService = { CaptureFilingService(vaultURL: $0) }) throws -> Outcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionError.emptyText }
        if let vaultURL {
            let filed = try makeService(vaultURL).file(text)
            let link = Noto2LaunchRoute.openNoteURL(relativePath: filed.relativePath) ?? Noto2LaunchRoute.quickCaptureURL
            return Outcome(relativePath: filed.relativePath, title: "Action completed",
                           body: (filed.didCreate ? "Saved to Noto 2: " : "Already in Noto 2: ") + preview(text),
                           link: link)
        }
        guard let store else { throw ActionError.nowhereToSave }
        let capture = try store.enqueue(body: text)
        return Outcome(stagedID: capture.id, title: "Action completed",
                       body: "Saved to Noto 2 (filed when Noto 2 next opens): " + preview(text),
                       link: Noto2LaunchRoute.openSharedCaptureURL(id: capture.id))
    }

    /// First line, at most 80 characters, quoted.
    static func preview(_ text: String) -> String {
        let firstLine = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let short = firstLine.count > 80 ? String(firstLine.prefix(79)) + "…" : firstLine
        return "“\(short)”"
    }
}

/// Posts the "Action completed" notification. Tapping it opens `link` (see Noto2NotificationDelegate).
enum ActionNotifier {
    static let linkKey = "link"

    static func post(title: String, body: String, link: URL) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info("notifications not authorized; skipping Action completed banner")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [linkKey: link.absoluteString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do { try await center.add(request) } catch {
            logger.error("notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Routes a tapped "Action completed" notification to its note, and shows banners while Noto 2 is
/// in the foreground. Set as the notification centre's delegate in `Noto2App.init`, so a tap that
/// launches the app is still delivered.
final class Noto2NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Noto2NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[ActionNotifier.linkKey] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run {
            _ = Noto2LaunchRouter.shared.handle(url, stageText: CaptureTextStager.stageInAppGroup)
        }
    }
}

/// The result of "Save Quick Capture", for the rest of the Shortcut: typically
/// Show Alert (Title, Message) → Open URLs (Link), so OK opens the note.
struct SavedCapture: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Saved Capture" }

    @Property(title: "Title") var title: String
    @Property(title: "Message") var message: String
    @Property(title: "Link") var link: URL?
    @Property(title: "Path") var path: String

    init() { title = ""; message = ""; link = nil; path = "" }

    init(_ outcome: QuickCaptureAction.Outcome) {
        self.init()
        title = outcome.title
        message = outcome.body
        link = outcome.link
        path = outcome.relativePath ?? ""
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(message)")
    }
}

/// Shortcuts action: save text as a Noto 2 quick-capture note without opening the app. Returns a
/// Saved Capture (title, message, link) for a Show Alert → Open URLs pair; can also post an
/// "Action completed" notification whose tap opens the note.
struct SaveQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource { "Save Quick Capture" }
    static var description: IntentDescription {
        IntentDescription("Saves text as a quick-capture note in Noto 2's inbox without opening the app. Returns a Saved Capture — show its Title and Message with Show Alert, then Open URLs with its Link to jump to the note. Optionally also posts a notification.")
    }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Text") var text: String

    @Parameter(title: "Notify When Done", description: "Also post an “Action completed” notification; tapping it opens the note.", default: false)
    var notify: Bool

    static var parameterSummary: some ParameterSummary { Summary("Save \(\.$text) to Noto 2") { \.$notify } }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SavedCapture> {
        let vault = VaultLocationManager(resolveExternalVaultOnInit: true)
        let vaultURL = vault.isVaultConfigured ? vault.vaultURL : nil
        let outcome = try QuickCaptureAction.run(text: text, vaultURL: vaultURL, store: PendingCaptureStore.appGroup())
        logger.info("saved quick capture path=\(outcome.relativePath ?? "-", privacy: .public) staged=\(outcome.stagedID?.uuidString ?? "-", privacy: .public)")
        if outcome.relativePath != nil {
            // Digest reloads if the app happens to be open.
            NotificationCenter.default.post(name: SharedCaptureDrain.didFileNotification, object: nil)
        }
        if notify { await ActionNotifier.post(title: outcome.title, body: outcome.body, link: outcome.link) }
        return .result(value: SavedCapture(outcome))
    }
}

/// Lists "Save Quick Capture" in Shortcuts, Spotlight and Siri without building a Shortcut first.
struct Noto2Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveQuickCaptureIntent(),
            phrases: ["Save a note in \(.applicationName)", "Quick capture in \(.applicationName)"],
            shortTitle: "Save Quick Capture",
            systemImageName: "square.and.pencil"
        )
    }
}
