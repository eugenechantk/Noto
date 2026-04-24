# Feature: Readwise Reader Save CLI

## Problem

`NotoReadwiseSync` is inbound-only today. `ReadwiseClient` fetches from `/api/v2/export/` and `/api/v3/list/` and writes markdown into the vault. There is no way to push a URL *to* Reader from the CLI. When Eugene comes across an article or video he wants in Reader's queue from a terminal context (e.g. from a Claude session), the only option is the Reader web UI or Save extension. Adding a CLI `--save` mode lets the same binary handle both directions.

## Success criteria

- `noto-readwise-sync --save <url>` saves one URL to Reader via `POST /api/v3/save/`, reports created/existing status and the Reader link.
- `--save` is repeatable for batch saves in one invocation.
- Metadata overrides (`--save-title`, `--save-author`, `--save-tag`, `--save-location`, `--save-category`, `--save-summary`, `--save-notes`, `--save-published-date`, `--save-image-url`) mirror the Reader Save API schema.
- Save mode is mutually exclusive with reader/export modes. Running `--save` alongside `--reader` errors out before any network call.
- `--dry-run` prints the payload without posting.
- Tests cover request encoding (snake_case keys, nil-field omission), response decoding, and CLI parsing.

## Shape

```
Usage:
  noto-readwise-sync --save <url> [options]
  noto-readwise-sync --save <url1> --save <url2> --save-tag ai [options]

Save mode options:
  --save <url>                  URL to save. Repeat for multiple URLs.
  --save-title <title>          Override detected title.
  --save-author <author>        Override detected author.
  --save-tag <tag>              Tag to attach. Repeat for multiple tags.
  --save-location <value>       new | later | archive | feed. Default: new.
  --save-category <type>        article | video | pdf | epub | tweet | rss | email.
  --save-summary <text>         Summary.
  --save-notes <text>           Top-level document note.
  --save-published-date <iso>   ISO 8601 published date.
  --save-image-url <url>        Cover image URL.
```

All metadata overrides apply to every URL in the run — batch saves assume a single intent (e.g. "save these three with `ai` tag"). Per-URL overrides are out of scope; rerun the command for different metadata.

## Non-goals

- Providing `html` payloads. Reader auto-scrapes; we always omit `html` and `should_clean_html`.
- Persisting save results into the vault. The existing inbound sync will pull the new docs into `Captures/` on the next scheduled run.
- Rate-limit backoff beyond the 50/min the existing client already handles via 429 + `Retry-After`.

## Implementation notes

- `SaveDocumentRequest` uses `encodeIfPresent` for all optional fields so the payload matches the API's "only send what you mean" convention.
- `SaveOutcome` captures `status` (`created` for HTTP 201, `existing` for 200) so CLI output can tell the user whether Reader already had the URL.
- `ReadwiseClient.saveReaderDocument(_:)` reuses the existing 429/`Retry-After` handling pattern from `fetchExportPage`.
- CLI parser: any `--save*` flag flips `saveMode = true`. If both `saveMode` and `readerMode` are set, throw `CLIError.conflictingModes`.
