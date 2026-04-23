# Feature: Readwise Source Sync CLI

## User Story

As Eugene, I want a local command that backfills my Readwise sources into the Noto vault so that articles, books, podcasts, tweets, and other highlighted sources become editable markdown source notes.

## User Flow

1. Eugene runs a local CLI with a Readwise access token and vault path.
2. The CLI fetches all Readwise export pages from `GET /api/v2/export/`.
3. Or Eugene runs the CLI in Reader mode to fetch saved Reader documents from `GET /api/v3/list/`.
4. The CLI writes one flat source note per source under `<vault>/Sources`.
5. Each note contains frontmatter, source/readwise/captured body metadata, a generated highlights block, and a generated content block.
6. The CLI stores sync state under `<vault>/.noto/sync/readwise.json`.
7. Re-running the CLI updates existing source notes by canonical key and only rewrites generated highlight/content blocks.

## Success Criteria

- [x] CLI builds as a local Swift executable package.
- [x] CLI can fetch paginated Readwise export data using `Authorization: Token <token>`.
- [x] CLI can dry-run without writing source notes.
- [x] CLI writes source notes to a flat `Sources/` directory.
- [x] CLI uses `updated:` frontmatter, not `modified:`.
- [x] CLI wraps generated highlights with `<!-- noto:highlights:start -->` and `<!-- noto:highlights:end -->`.
- [x] CLI wraps generated content with `<!-- noto:content:start -->` and `<!-- noto:content:end -->`.
- [x] CLI body metadata contains only source, optional Readwise link, and captured date.
- [x] CLI preserves markdown outside generated blocks on subsequent syncs.
- [x] Readwise-highlight sync preserves an existing Reader content block.
- [x] CLI writes hidden sync state with source mappings and sync timestamps.
- [x] Unit tests cover rendering, filename conflicts, and generated-block replacement.
- [x] CLI imports Reader documents with `withHtmlContent=true`.
- [x] CLI supports importing one Reader document by id.
- [x] Reader full-content notes use `capture_status: full`.
- [x] Reader imports skip child documents such as highlights/notes.

## Platform & Stack

- Platform: local CLI
- Language: Swift
- Key frameworks: Foundation, Swift Package Manager, Swift Testing

## Steps to Verify

1. `cd Packages/NotoReadwiseSync && swift test` - passed.
2. `cd Packages/NotoReadwiseSync && swift run noto-readwise-sync --help` - passed.
3. `cd Packages/NotoReadwiseSync && swift run noto-readwise-sync --vault <temp-vault> --fixture <fixture.json>` - passed.
4. Verify notes are created in `<temp-vault>/Sources` - passed.
5. Edit text outside generated blocks and rerun the fixture sync - passed.
6. Verify the manual text remains while generated highlights update - passed.
7. `swift run noto-readwise-sync --vault <temp-vault> --reader --fixture <reader-fixture.json>` - passed.
8. `swift run noto-readwise-sync --vault <vault> --reader-id <reader-id> --dry-run` - passed.
9. `swift run noto-readwise-sync --vault <vault> --reader-id <reader-id>` - passed.

## Bugs

_None yet._
