import Testing
@testable import Noto2

struct NoteEditorOptionsTests {
    @Test func exposesEveryRequestedEditorOption() {
        #expect(Noto2NoteEditorOption.allCases == [
            .pin,
            .properties,
            .moveNote,
            .searchInNote,
            .copyLink,
            .share,
            .deleteNote
        ])
    }
}
