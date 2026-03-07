# Spec: DateFilterParser -- "this year" / "last year" Extension

## Changes

**File:** `Packages/NotoSearch/Sources/NotoSearch/DateFilterParser.swift`

### New patterns added to `patterns` array (indices 8 and 9)

1. **"this year"** (index 8)
   - Regex: `\bthis\s+year\b` (case insensitive)
   - Date range: Calendar components extract current year, set month=1, day=1 for start. End = now.

2. **"last year" / "last year's"** (index 9)
   - Regex: `\blast\s+year(?:'s)?\b` (case insensitive)
   - Date range: Start = Jan 1 of (currentYear - 1). End = Jan 1 of currentYear.

### Switch case updates in `parse(_:now:)`

- Cases 7, 8, 9 now grouped together (all use closure-based dateRange, no capture group extraction needed)
- Old cases 8, 9, 10 ("in Month Year", "in Month", "in Year") renumbered to 10, 11, 12

## Tests

**File:** `Packages/NotoSearch/Tests/NotoSearchTests/SearchTests.swift`

4 new tests using Swift Testing framework:

| Test | Validates |
|---|---|
| `dateFilterParserExtractsThisYear` | "what I wrote this year" -> text "what I wrote", range Jan 1 2026 to now |
| `dateFilterParserExtractsLastYear` | "notes from last year" -> text "notes from", range Jan 1 2025 to Jan 1 2026 |
| `dateFilterParserExtractsLastYearPossessive` | "last year's goals" -> text "goals", year 2025 |
| `dateFilterParserThisYearEmbeddedInQuery` | "projects this year about swift" -> text "projects about swift" |

All tests use injectable `now` parameter for deterministic assertions.
