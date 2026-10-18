import Foundation
import NotoDigest
import Observation

/// A lightweight tab presentation model. Inbox remains the source of due counts.
@MainActor
@Observable
final class InboxBadgeModel {
    private(set) var count = 0
    private var revision = 0

    func refresh(vaultURL: URL?, now: Date = Date()) async {
        revision += 1
        let request = revision
        guard let vaultURL else { count = 0; return }
        let dueCount = await Task.detached(priority: .utility) {
            DigestInbox(vaultURL: vaultURL).dueEntries(now: now).count
        }.value
        guard request == revision, !Task.isCancelled else { return }
        count = dueCount
    }
}
