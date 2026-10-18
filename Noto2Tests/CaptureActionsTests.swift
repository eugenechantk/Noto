import Foundation
import Testing
@testable import Noto2

/// Test case index — Capture's ✓ button and the card's context menu (C2, C4, C6).
/// 1. fileButtonNeedsTextAVaultAndIdle — ✓ is enabled only for a non-blank draft, a vault, and no filing in flight
/// 2. menuListsTheFiveActionsInOrder — File, Add to, New note, Copy, Discard
/// 3. onlyDiscardIsDestructive — Discard is the one red item
/// 4. everyActionNeedsText — a blank draft disables the whole menu
/// 5. filingActionsAlsoNeedAVault — Copy and Discard work without a vault; filing does not
/// 6. menuItemsHaveStableIdentifiers — automation contracts for the simulator audit
struct CaptureActionsTests {
    @Test func fileButtonNeedsTextAVaultAndIdle() {
        #expect(CaptureActions.canFile(draft: "a thought", hasVault: true, isBusy: false))
        #expect(!CaptureActions.canFile(draft: "   \n", hasVault: true, isBusy: false))
        #expect(!CaptureActions.canFile(draft: "a thought", hasVault: false, isBusy: false))
        #expect(!CaptureActions.canFile(draft: "a thought", hasVault: true, isBusy: true))
    }

    @Test func menuListsTheFiveActionsInOrder() {
        #expect(CaptureMenuAction.allCases == [.fileToInbox, .addToNote, .newNote, .copyText, .discard])
        #expect(CaptureMenuAction.allCases.map(\.title) == [
            "File to Inbox", "Add to note…", "New note…", "Copy text", "Discard",
        ])
    }

    @Test func onlyDiscardIsDestructive() {
        #expect(CaptureMenuAction.allCases.filter(\.isDestructive) == [.discard])
    }

    @Test func everyActionNeedsText() {
        for action in CaptureMenuAction.allCases {
            #expect(!action.isEnabled(draft: "  ", hasVault: true), "\(action) should be off for a blank draft")
            #expect(action.isEnabled(draft: "text", hasVault: true))
        }
    }

    @Test func filingActionsAlsoNeedAVault() {
        #expect(!CaptureMenuAction.fileToInbox.isEnabled(draft: "text", hasVault: false))
        #expect(!CaptureMenuAction.addToNote.isEnabled(draft: "text", hasVault: false))
        #expect(!CaptureMenuAction.newNote.isEnabled(draft: "text", hasVault: false))
        #expect(CaptureMenuAction.copyText.isEnabled(draft: "text", hasVault: false))
        #expect(CaptureMenuAction.discard.isEnabled(draft: "text", hasVault: false))
    }

    @Test func menuItemsHaveStableIdentifiers() {
        #expect(CaptureMenuAction.allCases.map(\.accessibilityIdentifier) == [
            "captureMenuFile", "captureMenuAddTo", "captureMenuNewNote", "captureMenuCopy", "captureMenuDiscard",
        ])
        #expect(Set(CaptureMenuAction.allCases.map(\.systemImage)).count == CaptureMenuAction.allCases.count)
    }
}
