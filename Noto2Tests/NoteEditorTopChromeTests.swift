import Testing
@testable import Noto2

struct NoteEditorTopChromeTests {
    @Test func matchesLFGFadeGeometryForStandardNavigationChrome() {
        let layout = Noto2EditorTopChromeLayout(chromeHeight: 103)

        #expect(layout.totalHeight == 139)
        #expect(abs(layout.statusBottom - (59.0 / 139.0)) < 0.000_001)
        #expect(abs(layout.chromeBottom - (103.0 / 139.0)) < 0.000_001)
    }

    @Test func clampsNegativeChromeHeightAndKeepsStopsOrdered() {
        let layout = Noto2EditorTopChromeLayout(chromeHeight: -20)

        #expect(layout.totalHeight == 36)
        #expect(layout.statusBottom == 0)
        #expect(layout.chromeBottom == 0)
    }
}
