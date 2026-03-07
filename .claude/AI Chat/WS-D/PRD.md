# PRD: DateFilterParser -- "this year" / "last year" Extension

## Problem

The DateFilterParser supports temporal phrases like "today", "this week", "last month", but lacks year-level granularity. Users searching with phrases like "what I wrote this year" or "last year's goals" get no date filtering applied.

## Goal

Add "this year" and "last year" temporal pattern recognition to DateFilterParser so that year-scoped queries produce correct date ranges and cleaned query text.

## Patterns to Support

| Input phrase | Date range |
|---|---|
| "this year" | Jan 1 of current year through now |
| "last year" | Jan 1 to Dec 31 of previous year |
| "last year's" (possessive) | Same as "last year" |

These patterns must work when embedded in longer queries (e.g., "what I wrote this year about swift" extracts "this year" and returns cleaned text "what I wrote about swift").

## Non-goals

- No "next year" or "N years ago" patterns
- No changes to SearchService or UI
