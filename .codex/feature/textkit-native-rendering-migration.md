# TextKit-Native Markdown Rendering Migration

## Goal

Move special Markdown rendering into TextKit's layout model wherever possible, so rendered elements reflow automatically when document layout changes. Manual overlays should remain only for editor chrome that is outside document content.

## Current State

The editor already has a useful semantic layer:

- `MarkdownBlockKind` detects headings, lists, todos, image links, XML-like tags, collapsed tag content, and paragraphs.
- `MarkdownParagraph` carries block-kind metadata through TextKit.
- `MarkdownTextDelegate` styles paragraphs and can return custom layout fragments.
- `HiddenFrontmatterLayoutFragment` is already a custom `NSTextLayoutFragment` for hidden/collapsed text.

The weak point is rendered controls:

- Todo circles are `UIButton` / `NSButton` overlays positioned from caret rects.
- Image previews are `UIImageView` / `NSImageView` overlays positioned from caret rects.
- XML collapse carets are overlay buttons positioned from caret rects.
- Hyperlinks are attributed inline text and should stay that way.

## Target Model

Use four rendering categories.

1. Attributed inline text
   - For inline semantics that are still text.
   - Examples: hyperlinks, bold, italic, strikethrough, inline code.

2. TextKit custom fragments
   - For visual text/block rendering that can be drawn and should participate in document layout.
   - Examples: muted XML tags, collapsed XML body, blockquotes/highlights, list marker drawing if needed.

3. Text attachments with view providers
   - For embedded block content or controls that need real UIKit/AppKit views.
   - Examples: image previews, potentially interactive todo checkbox views.

4. Layout-driven gutter overlays
   - For editor controls that are not document content.
   - Examples: XML collapse caret, future line-level editor affordances.

## Element Decisions

### Hyperlinks

Keep as attributed inline text.

They already flow with the paragraph and do not need custom fragments. Continue to render the title with `.link`, link color, and underline while hiding Markdown syntax when the caret is outside the line.

### Bullets and Ordered Lists

Prefer TextKit paragraph/list styling first.

Near-term:
- Keep prefix styling and paragraph indentation in `MarkdownParagraphStyler`.
- Avoid overlay views.

Future improvement:
- Consider `NSTextList` / `NSTextListElement` only if it can preserve Markdown source editing without introducing platform drift.
- If custom marker drawing is needed, use a custom fragment for list paragraphs rather than overlay markers.

### Todo Items

Migrate from overlay buttons to a TextKit-native implementation.

Recommended first target:
- Draw the checkbox in a custom todo paragraph layout fragment.
- Handle taps through text layout hit testing against the fragment's checkbox rect.
- Keep `- [ ]` / `- [x]` as backing Markdown.

Escalate to attachment view provider only if drawn hit testing/accessibility is not good enough.

Important constraints:
- Backing Markdown remains editable.
- Empty todo prefix `- [ ] ` must keep stable caret metrics.
- Toggle must participate in undo/redo.
- VoiceOver needs a usable action for the checkbox.

### Image Blocks

Migrate to `NSTextAttachment` + `NSTextAttachmentViewProvider`.

Rationale:
- Image previews are embedded block content.
- They need reserved layout height.
- They may need real views for async image loading, clipping, placeholders, and future interactions.

Implementation direction:
- Replace visual overlay image previews with a layout placeholder at the Markdown image line.
- Use attachment bounds to reserve height and width.
- Use a view provider for image loading and display.
- Keep backing Markdown editable. If replacing the whole line with an attachment creates poor editing behavior, use a custom block fragment first and defer view-provider adoption.

### XML-Like Tags and Collapsible Blocks

Move collapsed block behavior deeper into TextKit layout.

Near-term:
- Keep the current custom fragment approach for hidden/collapsed content.
- Ensure collapsed ranges suppress any native rendered child elements.

Target:
- Model XML blocks as explicit semantic ranges/elements.
- Collapse by excluding body content from layout or using zero-height fragments, similar to Apple's TextKit 2 comment hiding pattern.
- Keep opening/closing tags muted.

### XML Collapse Caret

Keep as editor chrome, but drive it from layout fragments rather than ad hoc caret rect refreshes.

Rationale:
- The caret is not Markdown document content.
- It should behave like a gutter fold control.

Target:
- During viewport/layout callbacks, derive opening-tag fragment frames.
- Position the button from fragment geometry.
- Rebuild only for visible fragments.
- Preserve large hit targets.

## Migration Phases

### Phase 1: Stabilize the Semantic Model

- Extract block metadata needed by rendering into shared structs.
- Make `MarkdownBlockKind` and parsed block ranges the source of truth.
- Add tests for block ranges, especially todos/images inside collapsed XML content.
- Keep current UI behavior unchanged.

### Phase 2: Replace Todo Overlays

- Add a todo-specific custom `NSTextLayoutFragment`.
- Draw checked/unchecked circle in the fragment.
- Keep prefix characters visually hidden but layout-stable.
- Add hit testing for checkbox toggles.
- Add accessibility action/label.
- Remove `todoCheckboxButtons` overlay arrays once parity is verified.

Validation:
- Single-line todos.
- Wrapped todos.
- Nested todos.
- Empty `- [ ] ` boundary.
- Toggle undo/redo.
- Collapse/expand XML above todo section.

### Phase 3: Replace Image Overlays

- Prototype image rendering as attachment view provider.
- Validate editing behavior around image Markdown lines.
- If attachment editing is awkward, use a custom image block fragment for reserved height and drawing first.
- Remove `imagePreviewViews` overlay arrays once parity is verified.

Validation:
- Remote image loads.
- Placeholder before load.
- Cached image render.
- Scroll past image block.
- No tall phantom line after image.
- Image inside collapsed XML is hidden.

### Phase 4: Make XML Collapse Layout-Native

- Move collapsed XML body handling from post-style attributes toward explicit layout participation.
- Hide/skips collapsed body content through TextKit element enumeration or zero-height custom fragments.
- Keep opening/closing tag styling muted and editable.

Validation:
- Multiple XML blocks.
- Nested-looking but non-nested XML-like ranges.
- Collapse state survives edits that shift ranges.
- Images/todos inside collapsed ranges do not render.

### Phase 5: Layout-Driven Gutter Controls

- Replace collapse caret positioning with a layout-driven gutter/control layer.
- Controls are derived from visible opening-tag fragments.
- Keep controls out of document flow.

Validation:
- Caret remains clickable after scroll.
- Caret remains clickable after selection changes.
- Caret remains aligned after collapse/expand.
- iPhone and iPad screenshots.

## Future Special Element Rule

For every future Markdown-rendered feature, choose the rendering class before implementation:

- Inline text style: attributed text.
- Visual paragraph/block decoration: custom layout fragment.
- Embedded interactive content: attachment view provider.
- Editor affordance outside content: layout-driven gutter overlay.

Do not add manual caret-rect overlays for document content unless it is explicitly temporary and covered by a migration note.

## Risks

- TextKit 2 custom fragments are more complex than overlays and need careful selection/caret testing.
- Attachment view providers may have awkward editing behavior when the backing Markdown should remain visible/editable.
- UIKit and AppKit TextKit behavior can diverge; each phase needs iOS, iPadOS, and macOS validation.
- Accessibility for drawn controls requires deliberate work.

## Recommendation

Start with todo items. They are small, visible, interactive, and currently expose the exact stale-overlay problem. If todo fragments work well, use the same pattern for other drawn controls. Then migrate image blocks separately because attachments/view providers have different risks.
