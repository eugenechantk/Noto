import NotoLinkPreview
import NotoShareCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2.share", category: "ShareViewController")

/// One sheet owns the entire share flow. Nothing is staged before Save;
/// success replaces the composer in place, then returns to the source app.
final class ShareViewController: UIViewController {
    private let model = ShareCaptureModel()
    private var didLoadItems = false
    private var didFinish = false
    private var content: UIHostingController<ShareCaptureSheet>?
    private var mediaDelivery: Task<Bool, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        let sheet = ShareCaptureSheet(
            model: model,
            onSave: { [weak self] in self?.save() },
            onClose: { [weak self] in self?.finish(cancelled: self?.model.isSaved != true) }
        )
        let host = UIHostingController(rootView: sheet)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didLoadItems else { return }
        didLoadItems = true
        Task { await loadSharedItems() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard didLoadItems, !didFinish else { return }
        finish(cancelled: !model.isSaved)
    }

    private func loadSharedItems() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let payload = await SharedItemLoader.payload(from: items)
        guard !didFinish else { return }
        guard let resolved = payload.resolve() else {
            model.state = .failure("Nothing shared looked like a web link.")
            return
        }
        model.draft = ShareCaptureDraft(resolved: resolved)
        model.preview = ShareLinkPreviewModel(url: resolved.url, fallbackTitle: resolved.title)
        model.isFromSafari = payload.pageTitle != nil
        model.state = .composing
    }

    private func save() {
        guard !didFinish, case .composing = model.state, let draft = model.draft else { return }
        guard let store = PendingCaptureStore.appGroup() else {
            model.saveError = "Noto 2's shared container isn't available on this build."
            return
        }
        model.state = .saving
        model.saveError = nil
        // This tiny atomic local write completes before showing success. The
        // vault and optional media job can be handled after the sheet closes.
        do {
            let capture = try store.enqueue(body: draft.body)
            startMediaJob(for: capture, url: draft.url, title: draft.title)
            model.state = .saved
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AccessibilityNotification.Announcement("Saved to Inbox").post()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.finish(cancelled: false)
            }
        } catch {
            logger.error("staging failed: \(String(describing: error), privacy: .public)")
            model.state = .composing
            model.saveError = "Couldn't save the link. Your thought is still here. Try again."
        }
    }

    private func startMediaJob(for capture: PendingCapture, url: URL, title: String?) {
        guard let job = ShareMediaJob.make(for: capture, url: url, title: title),
              let outbox = ShareMediaOutbox.appGroup(),
              let endpoint = ShareMediaEndpoint(infoDictionary: Bundle.main.infoDictionary) else { return }
        // Stage synchronously: dismissing the extension must never race the
        // first outbox write. Delivery remains opportunistic and retryable.
        do { try outbox.enqueue(job) } catch {
            logger.error("could not stage media job: \(String(describing: error), privacy: .public)")
            return
        }
        let dispatcher = ShareMediaDispatcher(outbox: outbox, endpoint: endpoint)
        mediaDelivery = Task { await dispatcher.deliver(job) }
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
