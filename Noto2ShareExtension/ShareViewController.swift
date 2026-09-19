import NotoShareCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2.share", category: "ShareViewController")

/// The share-sheet entry for Noto 2. It reads the shared URL (and page title,
/// when Safari's preprocessing script ran), stages `[title](url)` in the App
/// Group for Noto 2 to file into `inbox/`, then shows a sheet: **Link
/// captured**, with "Keep editing" (opens the app straight into that
/// capture note) and a close button. Staging rather than writing the vault
/// directly is deliberate — see `PendingCaptureStore`.
final class ShareViewController: UIViewController {
    private var didPresent = false
    private var didFinish = false
    private var content: UIHostingController<LinkCapturedSheet>?

    override func viewDidLoad() {
        super.viewDidLoad()
        // iOS presents the extension inside its own sheet container; paint it
        // in Noto's dark surface so the sheet reads as one piece.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = LinkCapturedSheet.uiBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true
        Task { await captureSharedItems() }
    }

    // MARK: - Work

    private func captureSharedItems() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let payload = await SharedItemLoader.payload(from: items)
        logger.info("share payload urls=\(payload.urls.count) texts=\(payload.texts.count) pageTitle=\(payload.pageTitle != nil)")

        guard let resolved = payload.resolve() else {
            presentSheet(.failure(message: "Nothing shared looked like a web link."))
            return
        }
        guard let store = PendingCaptureStore.appGroup() else {
            logger.error("App Group container unavailable")
            presentSheet(.failure(message: "Noto 2's shared container isn't available on this build."))
            return
        }
        do {
            let capture = try store.enqueue(body: resolved.body)
            logger.info("staged shared capture \(capture.id.uuidString, privacy: .public)")
            presentSheet(.captured(LinkCapturedSheet.Capture(
                id: capture.id,
                title: resolved.title ?? resolved.url.absoluteString,
                host: resolved.url.host ?? resolved.url.absoluteString
            )))
        } catch {
            logger.error("staging failed: \(String(describing: error), privacy: .public)")
            presentSheet(.failure(message: "Couldn't save the link. Try again."))
        }
    }

    // MARK: - Sheet

    private func presentSheet(_ state: LinkCapturedSheet.State) {
        let sheet = LinkCapturedSheet(
            state: state,
            onKeepEditing: { [weak self] id in self?.openNoteInNoto2(id: id) },
            onClose: { [weak self] in self?.finish(cancelled: false) }
        )
        let host = UIHostingController(rootView: sheet)
        host.view.backgroundColor = LinkCapturedSheet.uiBackground
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.alpha = 0
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        content = host
        UIView.animate(withDuration: 0.2) { host.view.alpha = 1 }
    }

    private func finish(cancelled: Bool) {
        guard !didFinish else { return }
        didFinish = true
        if cancelled {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Opening Noto 2

    /// Share extensions have no first-class "open my app" API.
    /// `extensionContext.open` reports false for share extensions, and UIKit
    /// refuses the legacy `openURL:` responder-chain trick outright
    /// ("needs to migrate to open(_:options:completionHandler:)"), so walk the
    /// responder chain to the application object and call the modern selector
    /// through its IMP. Verified on iOS 26 simulator.
    private func openNoteInNoto2(id: UUID) {
        let url = Noto2LaunchRoute.openSharedCaptureURL(id: id)
        logger.info("opening Noto 2 with \(url.absoluteString, privacy: .public)")
        let opened = openViaResponderChain(url)
        if !opened, let context = extensionContext {
            context.open(url) { [weak self] contextOpened in
                logger.info("extensionContext.open → \(contextOpened)")
                DispatchQueue.main.async { self?.finish(cancelled: false) }
            }
            return
        }
        // Give the host a beat to start the app switch before the extension goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.finish(cancelled: false)
        }
    }

    /// Walks to the application object — `UIWindowScene` also answers this
    /// selector but forwards it to something that raises
    /// `doesNotRecognizeSelector` (crashes the extension), so scenes are
    /// skipped on purpose.
    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector), let implementation = current.method(for: selector) {
                typealias Completion = @convention(block) (Bool) -> Void
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, URL, NSDictionary, Completion?) -> Void
                let open = unsafeBitCast(implementation, to: OpenURLFunction.self)
                let completion: Completion = { success in
                    logger.info("UIApplication open completion success=\(success)")
                }
                logger.info("open(_:options:completionHandler:) via \(String(describing: type(of: current)), privacy: .public)")
                open(current, selector, url, [:], completion)
                return true
            }
            responder = current.next
        }
        logger.error("no UIApplication in the responder chain")
        return false
    }
}

// MARK: - Sheet content

/// "Link captured" — the confirmation sheet. HIG sheet header: leading circular
/// ✕ (close); the confirm action is the labelled primary button in the body
/// ("Keep editing"), which reads better than a bare ✓ here.
struct LinkCapturedSheet: View {
    struct Capture {
        let id: UUID
        let title: String
        let host: String
    }

    enum State {
        case captured(Capture)
        case failure(message: String)
    }

    static let uiBackground = UIColor(red: 0x0E / 255, green: 0x11 / 255, blue: 0x16 / 255, alpha: 1)

    let state: State
    let onKeepEditing: (UUID) -> Void
    let onClose: () -> Void

    private let accent = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x2E / 255)
    private let card = Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x27 / 255)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)
                .padding(.horizontal, 12)
            content
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0x0E / 255, green: 0x11 / 255, blue: 0x16 / 255).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("linkCapturedSheet")
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityIdentifier("linkCapturedTitle")
            HStack {
                circleButton(systemName: "xmark", identifier: "linkCapturedCloseButton", label: "Close", action: onClose)
                Spacer()
            }
        }
        .frame(height: 44)
    }

    private var title: String {
        switch state {
        case .captured: return "Link captured"
        case .failure: return "Couldn't capture link"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .captured(let capture):
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capture.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .accessibilityIdentifier("linkCapturedLinkTitle")
                        Text(capture.host)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                Text("Saved to your inbox as a quick capture.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))

                Button {
                    onKeepEditing(capture.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("Keep editing")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("linkCapturedKeepEditingButton")
            }
        case .failure(let message):
            VStack(alignment: .leading, spacing: 14) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityIdentifier("linkCapturedErrorMessage")
                Button(action: onClose) {
                    Text("Close")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func circleButton(systemName: String, identifier: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Item providers

/// Pulls URLs, plain text, and the JavaScript preprocessing result out of the
/// share sheet's item providers. A provider that declines a type simply
/// contributes nothing.
enum SharedItemLoader {
    static func payload(from items: [NSExtensionItem]) async -> SharedLinkPayload {
        var payload = SharedLinkPayload()
        for item in items {
            if let title = item.attributedTitle?.string, !title.isEmpty {
                payload.itemTitle = payload.itemTitle ?? title
            }
            if let text = item.attributedContentText?.string, !text.isEmpty {
                payload.texts.append(text)
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    let results = await loadPreprocessingResults(from: provider)
                    if let title = results["title"] as? String, !title.isEmpty {
                        payload.pageTitle = title
                    }
                    if let urlString = results["url"] as? String, let url = URL(string: urlString) {
                        payload.urls.append(url)
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider) {
                    payload.urls.append(url)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(from: provider), !text.isEmpty {
                    payload.texts.append(text)
                }
            }
        }
        // De-duplicate: Safari hands the same URL as `public.url` and via the script.
        var seen = Set<String>()
        payload.urls = payload.urls.filter { seen.insert($0.absoluteString).inserted }
        var seenText = Set<String>()
        payload.texts = payload.texts.filter { seenText.insert($0).inserted }
        return payload
    }

    private static func loadPreprocessingResults(from provider: NSItemProvider) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) { item, _ in
                let dictionary = item as? [String: Any]
                let results = dictionary?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                continuation.resume(returning: results ?? [:])
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else if let attributed = item as? NSAttributedString {
                    continuation.resume(returning: attributed.string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
