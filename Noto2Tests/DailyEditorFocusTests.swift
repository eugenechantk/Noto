import SwiftUI
import Testing
import UIKit
@testable import Noto2

@MainActor
@Suite(.serialized)
struct DailyEditorFocusTests {
    @Test func focusingDailyEditorHidesTabsAndResigningRestoresThem() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = try await fixture.dailyEditor()
        let tabs = try await fixture.tabController()
        #expect(fixture.isTabBarVisible(tabs))

        try #require(editor.textView.becomeFirstResponder())
        #expect(editor.textView.isFirstResponder)
        #expect(editor.textView.inputAccessoryView != nil)
        #expect(await fixture.waitUntil { !fixture.isTabBarVisible(tabs) },
                "Focused Daily editor must hide tabs even when only its accessory is visible")

        try #require(editor.textView.resignFirstResponder())
        #expect(await fixture.waitUntil { fixture.isTabBarVisible(tabs) })
    }

    @Test func leavingDailyRestoresTabsAndReturningMatchesActualEditorFocus() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = try await fixture.dailyEditor()
        let tabs = try await fixture.tabController()
        try #require(editor.textView.becomeFirstResponder())
        #expect(await fixture.waitUntil { !fixture.isTabBarVisible(tabs) })

        fixture.selection.value = 1
        #expect(await fixture.waitUntil { tabs.selectedIndex == 1 && fixture.isTabBarVisible(tabs) })

        fixture.selection.value = 0
        #expect(await fixture.waitUntil { tabs.selectedIndex == 0 && editor.view.window != nil })
        #expect(await fixture.waitUntil {
            fixture.isTabBarVisible(tabs) != editor.textView.isFirstResponder
        })
        editor.textView.resignFirstResponder()
        #expect(await fixture.waitUntil { fixture.isTabBarVisible(tabs) })
    }

    @Test func changingDayReplacesFocusedEditorAndEmptyDayRestoresTabs() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = try await fixture.dailyEditor()
        let tabs = try await fixture.tabController()
        let todaySession = try #require(fixture.model.session)
        let todayURL = todaySession.note.fileURL
        try #require(editor.textView.becomeFirstResponder())
        editor.textView.selectedRange = NSRange(location: editor.textView.text.utf16.count, length: 0)
        editor.textView.insertText("\nDaily focus draft.")
        try #require(await fixture.waitUntil { todaySession.latestEditorText.contains("Daily focus draft.") })

        await fixture.model.previousDay()
        let replacement = try await fixture.dailyEditor()
        #expect(replacement !== editor)
        #expect(await fixture.waitUntil { !editor.textView.isFirstResponder && editor.view.window == nil })
        #expect(await fixture.waitUntil { fixture.isTabBarVisible(tabs) })
        #expect(!replacement.textView.isFirstResponder)
        #expect(fixture.model.selectedDate == fixture.pastDay)
        #expect(try String(contentsOf: todayURL, encoding: .utf8).contains("Daily focus draft."))
        #expect(replacement.textView.text == fixture.pastMarkdown)

        try #require(replacement.textView.becomeFirstResponder())
        #expect(await fixture.waitUntil { !fixture.isTabBarVisible(tabs) })
        await fixture.model.previousDay()
        #expect(fixture.model.session == nil)
        #expect(await fixture.waitUntil { !replacement.textView.isFirstResponder && replacement.view.window == nil })
        #expect(await fixture.waitUntil { fixture.isTabBarVisible(tabs) })
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Daily Notes/2026-10-15.md").path))
    }

    @Test func swiftUIUpdatesFocusCallbackAndControllerReappearanceKeepsReporting() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = try await fixture.dailyEditor()
        let events = FocusEvents()
        let host = UIHostingController(rootView: CallbackEditor(events: events, generation: 0))
        fixture.window.rootViewController = host
        let editor = try await fixture.editor(in: host)
        try #require(editor.textView.becomeFirstResponder())
        #expect(events.values == ["0:true"])

        host.rootView = CallbackEditor(events: events, generation: 1)
        fixture.window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try #require(editor.textView.resignFirstResponder())
        #expect(events.values == ["0:true", "1:false"])
        try #require(editor.textView.becomeFirstResponder())
        #expect(events.values.last == "1:true")

        fixture.window.rootViewController = UIViewController()
        #expect(await fixture.waitUntil { events.values.last == "1:false" })
        fixture.window.rootViewController = host
        _ = try await fixture.editor(in: host)
        try #require(editor.textView.becomeFirstResponder())
        #expect(events.values.last == "1:true")
        editor.textView.resignFirstResponder()
        #expect(events.values.last == "1:false")
    }

    @MainActor
    private final class FocusEvents {
        var values: [String] = []
    }

    private struct CallbackEditor: View {
        let events: FocusEvents
        let generation: Int

        var body: some View {
            TextKit2EditorView(
                text: .constant("# Focus callback\n"),
                onFocusChange: { focused in events.values.append("\(generation):\(focused)") }
            )
        }
    }

    @MainActor
    @Observable
    final class Selection {
        var value = 0
    }

    private struct Tabs: View {
        let model: TodayModel
        @Bindable var selection: Selection

        var body: some View {
            TabView(selection: $selection.value) {
                TodayScreen(model: model)
                    .tabItem { Label("Daily Notes", systemImage: "calendar") }
                    .tag(0)
                Text("Other flow")
                    .tabItem { Label("Other", systemImage: "tray") }
                    .tag(1)
            }
            .preferredColorScheme(.dark)
        }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let selection = Selection()
        let model: TodayModel
        let pastDay: Date
        let pastMarkdown: String
        let window: UIWindow
        let host: UIHostingController<Tabs>
        private weak var previousKeyWindow: UIWindow?

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("DailyEditorFocus-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
            let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
            pastDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
            pastMarkdown = "# Existing past day\n\nWriting from yesterday.\n"
            let dailyFolder = root.appendingPathComponent("Daily Notes")
            try FileManager.default.createDirectory(at: dailyFolder, withIntermediateDirectories: true)
            try pastMarkdown.write(to: dailyFolder.appendingPathComponent("2026-10-16.md"), atomically: true, encoding: .utf8)
            model = TodayModel(
                vaultController: VaultController(vaultURL: root, autoloadRoot: false),
                calendar: calendar,
                now: { today }
            )
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            host = UIHostingController(rootView: Tabs(
                model: model,
                selection: selection
            ))
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
        }

        func close() {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            model.session?.cancelBackgroundWork()
            previousKeyWindow?.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: root)
        }

        func dailyEditor() async throws -> TextKit2EditorViewController {
            _ = await waitUntil { self.model.session != nil && !self.model.isLoading }
            let session = try #require(model.session)
            return try await editor(in: host, documentID: session.note.id.uuidString)
        }

        func editor(in root: UIViewController, documentID: String? = nil) async throws -> TextKit2EditorViewController {
            _ = await waitUntil {
                self.controllers(in: root).contains {
                    guard let editor = $0 as? TextKit2EditorViewController else { return false }
                    return editor.viewIfLoaded?.window != nil && !editor.textView.text.isEmpty
                        && (documentID == nil || editor.coordinator?.lastDocumentID == documentID)
                }
            }
            return try #require(controllers(in: root).compactMap { $0 as? TextKit2EditorViewController }.first {
                $0.viewIfLoaded?.window != nil && (documentID == nil || $0.coordinator?.lastDocumentID == documentID)
            })
        }

        func tabController() async throws -> UITabBarController {
            _ = await waitUntil { self.controllers(in: self.host).contains { $0 is UITabBarController } }
            return try #require(controllers(in: host).compactMap { $0 as? UITabBarController }.first)
        }

        func waitUntil(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<150 {
                window.layoutIfNeeded()
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return condition()
        }

        func isTabBarVisible(_ tabs: UITabBarController) -> Bool {
            let bar = tabs.tabBar
            guard bar.window === window, !bar.isHidden, bar.alpha > 0.01 else { return false }
            var ancestor = bar.superview
            while let view = ancestor {
                if view.isHidden || view.alpha <= 0.01 { return false }
                ancestor = view.superview
            }
            let visible = bar.convert(bar.bounds, to: window).intersection(window.bounds)
            return !visible.isNull && visible.width > 1 && visible.height > 1
        }

        private func controllers(in root: UIViewController) -> [UIViewController] {
            [root] + root.children.flatMap { controllers(in: $0) }
        }
    }
}
