import Testing
@testable import Noto2

struct NoteEditorOptionsTests {
    @Test func exposesEveryRequestedEditorOption() {
        #expect(Noto2NoteEditorOption.allCases == [
            .searchInNote,
            .properties,
            .moveNote,
            .deleteNote,
            .wordCount,
            .characterCount
        ])
    }
}
