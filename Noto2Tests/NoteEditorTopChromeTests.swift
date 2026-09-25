import Testing
@testable import Noto2

struct NoteEditorTopChromeTests {
    @Test func matchesLFGFadeGeometryForStandardNavigationChrome() {
        let layout = Noto2TopChromeLayout(chromeHeight: 103)

        #expect(layout.totalHeight == 139)
        #expect(abs(layout.statusBottom - (59.0 / 139.0)) < 0.000_001)
        #expect(abs(layout.chromeBottom - (103.0 / 139.0)) < 0.000_001)
    }

    @Test func clampsNegativeChromeHeightAndKeepsStopsOrdered() {
        let layout = Noto2TopChromeLayout(chromeHeight: -20)

        #expect(layout.totalHeight == 36)
        #expect(layout.statusBottom == 0)
        #expect(layout.chromeBottom == 0)
    }

    @Test func explorerControlRowKeepsFullOpacityThroughStatusRegion() {
        let layout = Noto2TopChromeLayout(chromeHeight: 103, barRow: 44)

        #expect(layout.totalHeight == 139)
        #expect(abs(layout.statusBottom - (59.0 / 139.0)) < 0.000_001)
        #expect(abs(layout.chromeBottom - (103.0 / 139.0)) < 0.000_001)
    }

    @Test func clampsNegativeControlRowHeight() {
        let layout = Noto2TopChromeLayout(chromeHeight: 59, barRow: -44)

        #expect(layout.statusBottom == layout.chromeBottom)
    }
}
