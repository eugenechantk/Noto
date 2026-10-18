import Foundation
import Testing
@testable import Noto2

@MainActor
struct Noto2StartupTests {
    /// Only Capture may launch without the vault workspace; Digest reads `inbox/`
    /// and picks destination notes, so it needs the workspace like Search/Browse.
    @Test func captureDoesNotRequireWorkspace() {
        #expect(!Noto2StartupPolicy.requiresWorkspace(.capture))
        #expect(Noto2StartupPolicy.requiresWorkspace(.digest))
        #expect(Noto2StartupPolicy.requiresWorkspace(.search))
        #expect(Noto2StartupPolicy.requiresWorkspace(.browse))
    }

    @Test func pendingExternalVaultCanPresentCaptureBeforeResolutionFinishes() {
        #expect(Noto2StartupPolicy.canPresentCapture(isConfigured: false, hasDeferredResolution: true))
        #expect(Noto2StartupPolicy.canPresentCapture(isConfigured: true, hasDeferredResolution: false))
        #expect(!Noto2StartupPolicy.canPresentCapture(isConfigured: false, hasDeferredResolution: false))
    }

    @Test func vaultControllerCanDeferRootEnumerationUntilBrowseNeedsIt() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Noto2StartupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        try "# Existing note".write(
            to: vaultURL.appendingPathComponent("Existing.md"),
            atomically: true,
            encoding: .utf8
        )

        let controller = VaultController(vaultURL: vaultURL, autoloadRoot: false)
        #expect(controller.rootItems.isEmpty)
        #expect(!controller.isLoadingRoot)

        controller.loadRoot()
        #expect(controller.rootItems.count == 1)
    }
}
