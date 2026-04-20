/// # Test Index
///
/// ## Block Type Detection
/// - `testParagraphType` — plain text → paragraph
/// - `testHeading1Type` — `# ` prefix → heading level 1
/// - `testHeading2Type` — `## ` prefix → heading level 2
/// - `testHeading3Type` — `### ` prefix → heading level 3
/// - `testTodoUncheckedType` — `- [ ] ` prefix → todo unchecked
/// - `testTodoCheckedType` — `- [x] ` prefix → todo checked
/// - `testBulletType` — `- ` prefix → bullet
/// - `testOrderedListType` — `1. ` prefix → ordered list
/// - `testIndentedBulletType` — `  - ` prefix → bullet level 2
/// - `testIndentedTodoType` — `  - [ ] ` prefix → todo level 2
/// - `testEmptyBlockIsParagraph` — empty string → paragraph
///
/// ## Parsing (Markdown → Blocks)
/// - `testParseSimpleParagraph` — single line → one block
/// - `testParseMultipleLines` — three lines → three blocks
/// - `testParseFrontmatter` — frontmatter preserved as first block
/// - `testParseFrontmatterPlusContent` — frontmatter + heading + body
/// - `testParsePreservesBlankLines` — blank lines become empty paragraph blocks
///
/// ## Serialization (Blocks → Markdown)
/// - `testSerializeSingleBlock` — one block → its text
/// - `testSerializeMultipleBlocks` — blocks joined with newline
/// - `testRoundTrip` — parse then serialize = original
/// - `testRoundTripWithFrontmatter` — frontmatter round-trips exactly
///
/// ## Block Operations
/// - `testSplitAtMiddle` — Enter in middle of text → two blocks
/// - `testSplitAtEnd` — Enter at end → current block + new empty block
/// - `testSplitAtStart` — Enter at start → empty block + current block
/// - `testSplitTodoContinues` — Enter on todo → new unchecked todo
/// - `testSplitBulletContinues` — Enter on bullet → new bullet
/// - `testSplitOrderedListContinues` — Enter on ordered list → next number
/// - `testSplitEmptyTodoBecomesParapraph` — Enter on empty todo → paragraph
/// - `testSplitEmptyBulletBecomesParagraph` — Enter on empty bullet → paragraph
/// - `testMergeWithPrevious` — Backspace at start → merge into previous
/// - `testMergeTodoIntoParagraph` — Backspace at start of todo → paragraph with combined text
/// - `testMergeFirstBlockNoOp` — Backspace at start of first block → no change

import Testing
@testable import Noto

// MARK: - Block Type Detection

@Suite("Block Type Detection")
struct BlockTypeDetectionTests {

    @Test("Plain text is paragraph")
    func testParagraphType() {
        let block = Block(text: "Hello world")
        #expect(block.blockType == .paragraph)
    }

    @Test("# prefix is heading 1")
    func testHeading1Type() {
        let block = Block(text: "# Title")
        #expect(block.blockType == .heading(level: 1))
    }

    @Test("## prefix is heading 2")
    func testHeading2Type() {
        let block = Block(text: "## Section")
        #expect(block.blockType == .heading(level: 2))
    }

    @Test("### prefix is heading 3")
    func testHeading3Type() {
        let block = Block(text: "### Subsection")
        #expect(block.blockType == .heading(level: 3))
    }

    @Test("- [ ] prefix is unchecked todo")
    func testTodoUncheckedType() {
        let block = Block(text: "- [ ] Buy milk")
        #expect(block.blockType == .todo(checked: false, indent: 0))
    }

    @Test("- [x] prefix is checked todo")
    func testTodoCheckedType() {
        let block = Block(text: "- [x] Done task")
        #expect(block.blockType == .todo(checked: true, indent: 0))
    }

    @Test("- [X] prefix is checked todo")
    func testTodoUppercaseCheckedType() {
        let block = Block(text: "- [X] Done task")
        #expect(block.blockType == .todo(checked: true, indent: 0))
    }

    @Test("- prefix is bullet")
    func testBulletType() {
        let block = Block(text: "- Item")
        #expect(block.blockType == .bullet(indent: 0))
    }

    @Test("1. prefix is ordered list")
    func testOrderedListType() {
        let block = Block(text: "1. First")
        #expect(block.blockType == .orderedList(number: 1, indent: 0))
    }

    @Test("Indented bullet is level 2")
    func testIndentedBulletType() {
        let block = Block(text: "  - Nested")
        #expect(block.blockType == .bullet(indent: 1))
    }

    @Test("Indented todo is level 2")
    func testIndentedTodoType() {
        let block = Block(text: "  - [ ] Nested task")
        #expect(block.blockType == .todo(checked: false, indent: 1))
    }

    @Test("Empty text is paragraph")
    func testEmptyBlockIsParagraph() {
        let block = Block(text: "")
        #expect(block.blockType == .paragraph)
    }
}

// MARK: - Parsing

@Suite("Markdown Parsing")
struct MarkdownParsingTests {

    @Test("Single line → one block")
    func testParseSimpleParagraph() {
        let blocks = BlockParser.parse("Hello world")
        #expect(blocks.count == 1)
        #expect(blocks[0].text == "Hello world")
    }

    @Test("Three lines → three blocks")
    func testParseMultipleLines() {
        let blocks = BlockParser.parse("Line one\nLine two\nLine three")
        #expect(blocks.count == 3)
        #expect(blocks[0].text == "Line one")
        #expect(blocks[1].text == "Line two")
        #expect(blocks[2].text == "Line three")
    }

    @Test("Frontmatter preserved as first block")
    func testParseFrontmatter() {
        let blocks = BlockParser.parse("---\nid: abc\n---")
        #expect(blocks.count == 1)
        #expect(blocks[0].text == "---\nid: abc\n---")
        #expect(blocks[0].blockType == .frontmatter)
    }

    @Test("Frontmatter + heading + body")
    func testParseFrontmatterPlusContent() {
        let blocks = BlockParser.parse("---\nid: abc\n---\n# Title\nBody")
        #expect(blocks.count == 3)
        #expect(blocks[0].blockType == .frontmatter)
        #expect(blocks[1].text == "# Title")
        #expect(blocks[2].text == "Body")
    }

    @Test("Blank lines become empty paragraph blocks")
    func testParsePreservesBlankLines() {
        let blocks = BlockParser.parse("Line one\n\nLine three")
        #expect(blocks.count == 3)
        #expect(blocks[1].text == "")
        #expect(blocks[1].blockType == .paragraph)
    }
}

// MARK: - Serialization

@Suite("Markdown Serialization")
struct MarkdownSerializationTests {

    @Test("One block → its text")
    func testSerializeSingleBlock() {
        let blocks = [Block(text: "Hello")]
        #expect(BlockSerializer.serialize(blocks) == "Hello")
    }

    @Test("Multiple blocks joined with newline")
    func testSerializeMultipleBlocks() {
        let blocks = [Block(text: "# Title"), Block(text: "Body")]
        #expect(BlockSerializer.serialize(blocks) == "# Title\nBody")
    }

    @Test("Parse then serialize = original")
    func testRoundTrip() {
        let markdown = "# Title\n\n- [ ] Task one\n- [x] Task two\n\n## Section\n\nBody text"
        let blocks = BlockParser.parse(markdown)
        let result = BlockSerializer.serialize(blocks)
        #expect(result == markdown)
    }

    @Test("Frontmatter round-trips exactly")
    func testRoundTripWithFrontmatter() {
        let markdown = "---\nid: abc\ncreated: 2026-01-01\n---\n# Title\nBody"
        let blocks = BlockParser.parse(markdown)
        let result = BlockSerializer.serialize(blocks)
        #expect(result == markdown)
    }
}

// MARK: - Block Operations

@Suite("Block Operations")
struct BlockOperationTests {

    @Test("Enter in middle splits into two blocks")
    func testSplitAtMiddle() {
        var doc = BlockDocument(blocks: [Block(text: "Hello world")])
        doc.split(blockIndex: 0, atOffset: 5)
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[0].text == "Hello")
        #expect(doc.blocks[1].text == " world")
    }

    @Test("Enter at end creates empty block after")
    func testSplitAtEnd() {
        var doc = BlockDocument(blocks: [Block(text: "Hello")])
        doc.split(blockIndex: 0, atOffset: 5)
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[0].text == "Hello")
        #expect(doc.blocks[1].text == "")
    }

    @Test("Enter at start creates empty block before")
    func testSplitAtStart() {
        var doc = BlockDocument(blocks: [Block(text: "Hello")])
        doc.split(blockIndex: 0, atOffset: 0)
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[0].text == "")
        #expect(doc.blocks[1].text == "Hello")
    }

    @Test("Enter on todo creates new unchecked todo")
    func testSplitTodoContinues() {
        var doc = BlockDocument(blocks: [Block(text: "- [ ] Task")])
        doc.split(blockIndex: 0, atOffset: 10) // at end
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[1].text == "- [ ] ")
    }

    @Test("Enter on bullet creates new bullet")
    func testSplitBulletContinues() {
        var doc = BlockDocument(blocks: [Block(text: "- Item")])
        doc.split(blockIndex: 0, atOffset: 6)
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[1].text == "- ")
    }

    @Test("Enter on ordered list continues with next number")
    func testSplitOrderedListContinues() {
        var doc = BlockDocument(blocks: [Block(text: "1. First")])
        doc.split(blockIndex: 0, atOffset: 8)
        #expect(doc.blocks.count == 2)
        #expect(doc.blocks[1].text == "2. ")
    }

    @Test("Enter on empty todo becomes paragraph")
    func testSplitEmptyTodoBecomesParagraph() {
        var doc = BlockDocument(blocks: [Block(text: "- [ ] ")])
        doc.split(blockIndex: 0, atOffset: 6)
        // The empty todo should become a plain paragraph (prefix removed)
        #expect(doc.blocks[0].text == "")
        #expect(doc.blocks[0].blockType == .paragraph)
        // No new block created — the empty prefix was just removed
        #expect(doc.blocks.count == 1)
    }

    @Test("Enter on empty bullet becomes paragraph")
    func testSplitEmptyBulletBecomesParagraph() {
        var doc = BlockDocument(blocks: [Block(text: "- ")])
        doc.split(blockIndex: 0, atOffset: 2)
        #expect(doc.blocks[0].text == "")
        #expect(doc.blocks[0].blockType == .paragraph)
        #expect(doc.blocks.count == 1)
    }

    @Test("Backspace at start merges into previous block")
    func testMergeWithPrevious() {
        var doc = BlockDocument(blocks: [Block(text: "Hello"), Block(text: "World")])
        let cursorOffset = doc.mergeWithPrevious(blockIndex: 1)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].text == "HelloWorld")
        #expect(cursorOffset == 5) // cursor at join point
    }

    @Test("Backspace at start of todo merges into paragraph")
    func testMergeTodoIntoParagraph() {
        var doc = BlockDocument(blocks: [Block(text: "First"), Block(text: "- [ ] Task")])
        let cursorOffset = doc.mergeWithPrevious(blockIndex: 1)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].text == "First- [ ] Task")
        #expect(cursorOffset == 5)
    }

    @Test("Backspace at start of first block does nothing")
    func testMergeFirstBlockNoOp() {
        var doc = BlockDocument(blocks: [Block(text: "First")])
        let cursorOffset = doc.mergeWithPrevious(blockIndex: 0)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].text == "First")
        #expect(cursorOffset == nil) // no-op
    }
}
