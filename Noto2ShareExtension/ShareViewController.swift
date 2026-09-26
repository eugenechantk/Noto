import NotoLinkPreview
import NotoShareCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2.share", category: "ShareViewController")

/// The share-sheet entry for Noto 2. It reads the shared URL (and page title,
/// when Safari's preprocessing script ran), stages `[title](url)` in the App
/// Group for Noto 2 to file into `inbox/`, then shows the **Link captured**
/// sheet (see `LinkCapturedSheet`): "Keep editing" opens the app straight into
/// that capture note; Close, the ✕, or a swipe down end the share.
/// Staging rather than writing the vault directly is deliberate — see `PendingCaptureStore`.
///
/// For an X or Instagram post it also sends a media job (through the App
/// Group outbox) to the Cloudflare queue that Hermes drains; Hermes downloads
/// the post's photos and videos and appends them to the capture note.
final class ShareViewController: UIViewController {
    private var didPresent = false
    private var didFinish = false
    private var content: UIHostingController<LinkCapturedSheet>?
    /// In-flight media-job send; `finish` waits briefly for it.
    private var mediaDelivery: Task<Bool, Never>?

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

    /// The host owns the sheet, so a swipe down never reaches a presentation
    /// delegate here; the view simply disappears. End the request like Close
    /// does — the capture is already staged by then.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard didPresent, !didFinish else { return }
        logger.info("sheet swiped away")
        finish(cancelled: false)
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
            let fetchesMedia = startMediaJob(for: capture, url: resolved.url, title: resolved.title)
            presentSheet(.captured(LinkCapturedSheet.Capture(
                id: capture.id,
                url: resolved.url,
                pageTitle: resolved.title,
                fetchesMedia: fetchesMedia
            )))
        } catch {
            logger.error("staging failed: \(String(describing: error), privacy: .public)")
            presentSheet(.failure(message: "Couldn't save the link. Try again."))
        }
    }

    /// Sends the X / Instagram media job. Returns whether one was started.
    private func startMediaJob(for capture: PendingCapture, url: URL, title: String?) -> Bool {
        guard let job = ShareMediaJob.make(for: capture, url: url, title: title) else { return false }
        guard let outbox = ShareMediaOutbox.appGroup(),
              let endpoint = ShareMediaEndpoint(infoDictionary: Bundle.main.infoDictionary) else {
            logger.error("share-media endpoint or App Group unavailable; media job not sent")
            return false
        }
        let dispatcher = ShareMediaDispatcher(outbox: outbox, endpoint: endpoint)
        mediaDelivery = Task {
            let accepted = await dispatcher.deliver(job)
            logger.info("media job \(job.captureId.uuidString, privacy: .public) accepted=\(accepted)")
            return accepted
        }
        return true
    }

    // MARK: - Sheet

    private func presentSheet(_ state: LinkCapturedSheet.State) {
        var preview: ShareLinkPreviewModel?
        if case .captured(let capture) = state {
            preview = ShareLinkPreviewModel(url: capture.url, fallbackTitle: capture.pageTitle)
        }
        let sheet = LinkCapturedSheet(
            state: state,
            preview: preview,
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
        let delivery = mediaDelivery
        Task { @MainActor [weak self] in
            // Give the media job up to 3 s to reach the Worker; if it does not,
            // it stays in the outbox and Noto 2 re-sends it on its next launch.
            if let delivery {
                _ = await withTaskGroup(of: Bool.self) { group -> Bool in
                    group.addTask { await delivery.value }
                    group.addTask { try? await Task.sleep(for: .seconds(3)); return false }
                    let first = await group.next() ?? false
                    group.cancelAll()
                    return first
                }
            }
            guard let self else { return }
            if cancelled {
                self.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            } else {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
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

/// "Link captured" — the confirmation sheet. Centred: a saved badge, the title,
/// a line about where it went, and the link as the same preview card the
/// editor shows. Pinned to the bottom: **Keep editing** (opens the capture note)
/// and **Close**. The ✕ top right and a swipe down also close it.
struct LinkCapturedSheet: View {
    struct Capture {
        let id: UUID
        let url: URL
        /// Safari's page title, shown on the card until the preview loads.
        let pageTitle: String?
        /// X / Instagram post whose photos and videos Hermes will add.
        var fetchesMedia = false
    }

    enum State {
        case captured(Capture)
        case failure(message: String)
    }

    static let uiBackground = UIColor(red: 0x0E / 255, green: 0x11 / 255, blue: 0x16 / 255, alpha: 1)
    static let accent = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x2E / 255)

    let state: State
    let preview: ShareLinkPreviewModel?
    let onKeepEditing: (UUID) -> Void
    let onClose: () -> Void

    @SwiftUI.State private var badgeBounce = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            GeometryReader { proxy in
                ScrollView {
                    mainContent
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            buttons
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: Self.uiBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("linkCapturedSheet")
        .onAppear { badgeBounce.toggle() }
    }

    // MARK: Pieces

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("linkCapturedCloseButton")
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            badge
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .accessibilityIdentifier("linkCapturedTitle")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityIdentifier(isFailure ? "linkCapturedErrorMessage" : "linkCapturedStatus")
            if let preview {
                LinkPreviewCard(content: preview.content, style: .share)
                    .padding(.top, 28)
                    .accessibilityIdentifier("linkCapturedLinkCard")
            }
        }
        .frame(maxWidth: 440)
    }

    private var badge: some View {
        let tint = isFailure ? Color(red: 1, green: 0x5A / 255, blue: 0x5F / 255) : Self.accent
        return ZStack {
            Circle().fill(tint.opacity(0.16))
            Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1.5)
            Image(systemName: isFailure ? "exclamationmark" : "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: badgeBounce)
        }
        .frame(width: 76, height: 76)
        .accessibilityElement()
        .accessibilityLabel(isFailure ? "Not saved" : "Saved")
        .accessibilityIdentifier("linkCapturedIcon")
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 12) {
                if case .captured(let capture) = state {
                    Button {
                        onKeepEditing(capture.id)
                    } label: {
                        Label("Keep editing", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Self.accent)
                    .controlSize(.large)
                    .accessibilityIdentifier("linkCapturedKeepEditingButton")
                }
                Button(action: onClose) {
                    Text("Close")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("linkCapturedDismissButton")
            }
        }
    }

    // MARK: Copy

    private var isFailure: Bool {
        if case .failure = state { return true }
        return false
    }

    private var title: String {
        isFailure ? "Couldn't capture link" : "Link captured"
    }

    private var message: String {
        switch state {
        case .captured(let capture):
            return capture.fetchesMedia
                ? "Saved to your inbox as a quick capture. Its photos and videos will be added in a minute."
                : "Saved to your inbox as a quick capture."
        case .failure(let message):
            return message
        }
    }
}

extension LinkPreviewCardStyle {
    /// Noto's dark theme (the extension can't see the app's `AppTheme`).
    static let share = LinkPreviewCardStyle(
        background: Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x2A / 255).opacity(0.55),
        border: Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x2A / 255),
        title: Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255),
        summary: Color(red: 0xD4 / 255, green: 0xD4 / 255, blue: 0xD4 / 255),
        host: Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8E / 255),
        placeholder: Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x2A / 255)
    )
}

/// The shared card's content for one URL, refreshed when the preview service
/// finishes fetching it.
@MainActor
@Observable
final class ShareLinkPreviewModel {
    private(set) var content: LinkPreviewCardContent

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let fallbackTitle: String?
    @ObservationIgnored private var token: NSObjectProtocol?

    init(url: URL, fallbackTitle: String?) {
        self.url = url
        self.fallbackTitle = fallbackTitle
        content = LinkPreviewCardContent.make(url: url, state: ShareLinkPreviews.service.state(for: url), fallbackTitle: fallbackTitle)
        token = NotificationCenter.default.addObserver(
            forName: LinkPreviewService.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let changed = notification.userInfo?[LinkPreviewService.urlUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                guard let self, changed == self.url else { return }
                self.content = LinkPreviewCardContent.make(url: self.url, state: ShareLinkPreviews.service.state(for: self.url), fallbackTitle: self.fallbackTitle)
            }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

/// The extension's own preview service: same fetchers as the app, cached in the
/// extension's Caches directory.
enum ShareLinkPreviews {
    @MainActor
    static let service: LinkPreviewService = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cache = LinkPreviewCache(directoryURL: caches.appendingPathComponent("LinkPreviews", isDirectory: true))
        let fetcher = CompositeLinkPreviewFetcher(primary: LinkPresentationFetcher(), secondary: OpenGraphFetcher())
        return LinkPreviewService(cache: cache, fetcher: fetcher)
    }()
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
