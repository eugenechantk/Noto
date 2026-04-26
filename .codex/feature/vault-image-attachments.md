# Feature: Vault Image Attachments

## User Story

As a Noto user, I want to attach images into markdown notes so that images are stored in my vault, sync across devices, and render with the same markdown image syntax as remote images.

## User Flow

1. On macOS, drag an image file onto the editor insertion point.
2. On iOS or iPadOS, tap an image button in the keyboard toolbar and select a photo.
3. Noto imports the image into one vault directory, compresses it for practical file size, and inserts a markdown image line.
4. The note renders that markdown line using the existing image renderer.
5. If the image file is missing or not yet downloaded from iCloud, the image block remains as a visible placeholder.

## Success Criteria

- [x] Imported images are stored under `Attachments/` in the vault.
- [x] Imported image filenames are sanitized, conflict-safe, and markdown-compatible.
- [x] Imported images are compressed without unnecessary quality loss; photo-like inputs become JPEG and alpha images stay PNG.
- [x] Inserted markdown uses normal image syntax: `![alt](Attachments/path.ext)`.
- [x] Local relative vault image paths render through the same TextKit image fragment path as remote images.
- [x] Missing or not-yet-synced local images render as an image placeholder instead of breaking the editor.
- [x] macOS supports drag-and-drop image import into the editor.
- [x] iOS/iPadOS supports photo selection from the keyboard toolbar.
- [x] Common image formats and HEIF/HEIC inputs are accepted when Apple image decoding supports them.

## Platform & Stack

- **Platform:** iOS, iPadOS, macOS
- **Language:** Swift
- **Key frameworks:** SwiftUI, UIKit, AppKit, TextKit 2, PhotosUI, ImageIO, UniformTypeIdentifiers

## Steps to Verify

1. Run focused Swift tests for attachment import, markdown insertion, and image path resolution.
2. Run FlowDeck build for the app target.
3. Run simulator validation for the iOS keyboard toolbar image button and image placeholder/rendering path where feasible.

## Implementation Phases

### Phase 1: Attachment Import Core

- Scope: Add vault attachment importer, image compression, markdown path generation, and tests.
- Success criteria covered: storage directory, filename safety, compression, markdown syntax, format acceptance.
- Verification gate: app-target Swift tests pass.

### Phase 2: Rendering Local Attachments

- Scope: Resolve relative image markdown paths against the vault root and load local file images through the existing image fragment renderer.
- Success criteria covered: local rendering, missing-file placeholder.
- Verification gate: TextKit markdown layout tests pass.

### Phase 3: Editor UI Entry Points

- Scope: macOS drag/drop and iOS/iPadOS keyboard toolbar photo picker import.
- Success criteria covered: user-facing import flows.
- Verification gate: FlowDeck build and simulator validation.

## Bugs

_None yet._

## Verification Record

- `flowdeck test --only VaultImageAttachmentTests` passed: 3 tests.
- `flowdeck test --only relativeVaultImageLinksResolveAgainstVaultRoot` passed: 1 test.
- `flowdeck build -D "My Mac"` passed.
- `flowdeck build` passed for iOS Simulator.
- Isolated iPhone simulator `Noto-ImageAttach-D47B42` (`28834A52-D474-44B5-856B-05F0BC19216C`): seeded vault, opened editor, tapped `insert_image_button`, selected a Photos sample image, verified markdown `![IMG_0111](Attachments/IMG_0111.jpg)` and `Attachments/IMG_0111.jpg` in the simulator vault.
- Isolated iPad simulator `Noto-ImageAttach-iPad-B68B8C` (`395AC37D-D019-42B8-87FA-7DBC2764C609`): seeded vault, opened editor, verified keyboard-visible `insert_image_button`.
- Evidence screenshots:
  - `.codex/evidence/image-attachments-ios-toolbar.jpg`
  - `.codex/evidence/image-attachments-ios-picker.jpg`
  - `.codex/evidence/image-attachments-ios-after-select.jpg`
  - `.codex/evidence/image-attachments-ipad-toolbar.jpg`
