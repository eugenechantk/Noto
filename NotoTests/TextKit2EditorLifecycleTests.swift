import Testing
@testable import Noto

#if os(iOS)
import UIKit

@Suite("TextKit2 Editor Lifecycle")
struct TextKit2EditorLifecycleTests {

    @MainActor
    @Test("Loading text before the view exists is deferred until the text view is created")
    func loadTextBeforeViewLoadsIsDeferred() {
        let controller = TextKit2EditorViewController()

        controller.loadText("# Title\nBody")
        controller.loadViewIfNeeded()

        #expect(controller.textView.text == "# Title\nBody")
    }
}
#endif
