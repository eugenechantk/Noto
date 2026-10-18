import Foundation
import NotoDigest

/// Add to note… and New note… straight from Capture (feature doc C7–C9).
///
/// The draft is first written to `inbox/` like any capture, then moved by the
/// same `DigestFiling` code the Inbox uses. That keeps one tested path for
/// "write the destination first, delete the capture only on success": if the
/// second step fails, the thought is waiting in the Inbox, never lost.
struct CaptureDirectFiling {
    struct Receipt: Equatable, Sendable {
        let noteURL: URL
        let draft: String
        let stagedCapture: CaptureFilingService.Filed
        let destinationUndo: DigestFiling.UndoReceipt
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        /// The capture reached the Inbox but could not be moved on.
        case leftInInbox(String)

        var description: String {
            switch self {
            case .leftInInbox(let reason): "Saved to your Inbox instead. \(reason)"
            }
        }
    }

    let vaultURL: URL
    var capture: CaptureFilingService
    var filing: DigestFiling

    init(vaultURL: URL) {
        let root = vaultURL.standardizedFileURL
        self.vaultURL = root
        capture = CaptureFilingService(vaultURL: root)
        filing = DigestFiling(vaultURL: root)
    }

    /// Appends the draft to the end of the note at `noteURL`.
    @discardableResult
    func add(_ draft: String, toNoteAt noteURL: URL) throws -> Receipt {
        let staged = try fileToInbox(draft)
        do {
            let undo = try filing.appendWithUndo(staged.entry, toNoteAt: noteURL)
            return try receipt(undo, stagedCapture: staged.filed, draft: draft)
        } catch let error as DigestFiling.FilingError {
            throw Failure.leftInInbox(error.message)
        }
    }

    /// Writes the draft as a new note in `folderURL`, named from its first line,
    /// with the Markdown exactly as written.
    @discardableResult
    func createNote(_ draft: String, inFolderAt folderURL: URL) throws -> Receipt {
        guard DigestMarkdown.noteTitle(fromFirstLineOf: draft) != nil else {
            throw DigestFiling.FilingError.invalidTitle
        }
        let staged = try fileToInbox(draft)
        do {
            let undo = try filing.createWithUndo(staged.entry, inFolderAt: folderURL)
            return try receipt(undo, stagedCapture: staged.filed, draft: draft)
        } catch let error as DigestFiling.FilingError {
            throw Failure.leftInInbox(error.message)
        }
    }

    /// Shared filing restores the exact destination bytes, refusing newer edits.
    /// Capture then removes only the temporary inbox file this action created.
    /// An identical capture that existed before the action remains in the Inbox.
    func undo(_ receipt: Receipt) throws {
        try filing.undo(receipt.destinationUndo)
        if receipt.stagedCapture.didCreate,
           !capture.undo(receipt.stagedCapture, matchingDocument: receipt.destinationUndo.capture.document) {
            throw Failure.leftInInbox("The destination was restored, but the Inbox copy could not be removed.")
        }
    }

    private func receipt(_ undo: DigestFiling.UndoReceipt, stagedCapture: CaptureFilingService.Filed, draft: String) throws -> Receipt {
        guard let noteURL = undo.destinationURL else {
            throw Failure.leftInInbox("Couldn't identify the destination note.")
        }
        return Receipt(noteURL: noteURL, draft: draft, stagedCapture: stagedCapture, destinationUndo: undo)
    }

    private func fileToInbox(_ draft: String) throws -> (filed: CaptureFilingService.Filed, entry: DigestEntry) {
        let filed = try capture.file(draft)
        guard let entry = DigestInbox(vaultURL: vaultURL).entry(at: filed.fileURL) else {
            throw Failure.leftInInbox("Couldn't read \(filed.relativePath) back.")
        }
        return (filed, entry)
    }
}
