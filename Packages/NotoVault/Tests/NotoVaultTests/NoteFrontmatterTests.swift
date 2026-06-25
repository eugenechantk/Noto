import Foundation
import Testing
@testable import NotoVault

@Suite("NoteFrontmatter — programmatic write stamping")
struct NoteFrontmatterTests {
    private let note = """
    ---
    id: a1b2c3d4-e5f6-7890-abcd-000000000002
    created: 2026-03-15T10:00:00Z
    modified: 2026-03-15T10:00:00Z
    ---
    # Shopping List

    - Fruits
    """

    @Test("stampingModified updates only the modified line, preserving id/created/body")
    func stampsModifiedOnly() {
        let date = ISO8601DateFormatter().date(from: "2026-06-25T12:00:00Z")!
        let out = NoteFrontmatter.stampingModified(note, to: date)
        #expect(out.contains("modified: 2026-06-25T12:00:00Z"))
        #expect(!out.contains("modified: 2026-03-15T10:00:00Z"))
        #expect(out.contains("id: a1b2c3d4-e5f6-7890-abcd-000000000002"))   // preserved
        #expect(out.contains("created: 2026-03-15T10:00:00Z"))             // preserved
        #expect(out.contains("# Shopping List\n\n- Fruits"))               // body preserved
    }

    @Test("stampingModified inserts a modified line when none exists")
    func insertsModifiedWhenMissing() {
        let md = "---\nid: a1b2c3d4-e5f6-7890-abcd-000000000002\ncreated: 2026-03-15T10:00:00Z\n---\nbody"
        let date = ISO8601DateFormatter().date(from: "2026-06-25T12:00:00Z")!
        let out = NoteFrontmatter.stampingModified(md, to: date)
        #expect(out.contains("modified: 2026-06-25T12:00:00Z"))
        #expect(out.contains("body"))
    }

    @Test("stampingModified is a no-op without frontmatter")
    func noopWithoutFrontmatter() {
        let md = "# Just a body\n- item"
        #expect(NoteFrontmatter.stampingModified(md, to: Date()) == md)
    }

    @Test("id(of:) reads the frontmatter UUID")
    func readsID() {
        #expect(NoteFrontmatter.id(of: note) == UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-000000000002"))
        #expect(NoteFrontmatter.id(of: "# no frontmatter") == nil)
    }
}
