import Testing
@testable import Noto

#if os(iOS)
import CoreGraphics

@Suite("Note List View")
struct NoteListViewTests {

    @Test("Bottom toolbar hides only when a software keyboard overlaps the screen")
    func bottomToolbarHidesForVisibleSoftwareKeyboard() {
        let screenBounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        #expect(
            NotoAppBottomToolbarKeyboardVisibility.isSoftwareKeyboardVisible(
                frameInScreen: CGRect(x: 0, y: 500, width: 390, height: 344),
                screenBounds: screenBounds
            )
        )

        #expect(
            !NotoAppBottomToolbarKeyboardVisibility.isSoftwareKeyboardVisible(
                frameInScreen: CGRect(x: 0, y: 844, width: 390, height: 344),
                screenBounds: screenBounds
            )
        )

        #expect(
            !NotoAppBottomToolbarKeyboardVisibility.isSoftwareKeyboardVisible(
                frameInScreen: CGRect(x: 0, y: 780, width: 390, height: 44),
                screenBounds: screenBounds
            )
        )
    }
}
#endif
