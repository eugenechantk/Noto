---
name: perf-audit
description: >
  Audit implementation for time and space complexity. Flag O(n log n) or O(n²) operations,
  unnecessary allocations, and redundant work. Distinguish between hot (in-memory) and cold
  (I/O-bound) operations. Suggest fixes that reduce complexity while preserving abstractions
  and code clarity.
---

# Performance Audit

Audit the specified file(s) for time and space complexity issues. The goal: flag operations
that are more complex than they need to be, and suggest fixes that reduce complexity without
sacrificing abstractions or readability.

## Process

1. Read the specified file(s)
2. For each method, determine:
   - Time complexity (O notation)
   - Space complexity (allocations)
   - Data source: is each collection access hitting the database or reading from memory?
3. Flag issues using the checklist below
4. Suggest a concrete fix for each issue
5. Verify fixes don't break existing tests
6. Report findings as a table:

| Method | Current | Issue | Fix | After Fix |
|---|---|---|---|---|
| `indentLine` | O(n) cold (DB) | Fetches all siblings via SwiftData | Scan entries backwards | O(k) hot (memory) |

## The Key Question

For every collection or relationship access, ask:

**"Does the caller already have this data in memory?"**

If yes, use the in-memory source. Database round-trips are orders of magnitude slower than
array scans, even when the algorithmic complexity is the same O(n).

Two kinds of O(n):
- **Hot O(n)**: scanning an in-memory array. Nanoseconds per element.
- **Cold O(n)**: resolving a SwiftData/CoreData relationship, which may fault from SQLite. Microseconds to milliseconds per element.

An O(k) scan of a local array almost always beats an O(n) fetch from the database, even if k ≈ n.

## What to Flag

### 1. Cold collection access when hot data exists

The most impactful issue. SwiftData relationships (`.children`, `.sortedChildren`, `.parent?.sortedChildren`)
can trigger database queries. If the same data is already in a local array (like `entries`), use that instead.

```swift
// BAD: cold — resolves SwiftData relationship, may hit SQLite
let siblings = parent.sortedChildren.filter { !$0.isArchived }
let prev = siblings.last(where: { $0.sortOrder < block.sortOrder })

// GOOD: hot — scans the in-memory array that's already loaded
for i in stride(from: index - 1, through: 0, by: -1) {
    if entries[i].block.parent?.id == parentId { ... }
}
```

### 2. O(n) allocation when you only need one element

Building a full array just to read one property.

```swift
// BAD: allocates array of all children, uses one
let children = root.sortedChildren.filter { !$0.isArchived }
let firstSort = children.first?.sortOrder ?? 1.0

// GOOD: read directly from known position
let firstChildSort = entries.count > 1 ? entries[1].block.sortOrder : 1.0
```

### 3. O(n²) or worse hidden in loops

A loop that calls an O(n) operation on each iteration.

```swift
// BAD: O(n²) — sortedChildren is O(n log n) called inside O(n) loop
for block in blocks {
    let siblings = block.parent?.sortedChildren ?? []  // O(n log n) each time
    ...
}
```

### 4. O(n log n) sort when data is already ordered

Re-sorting a list that's already in order.

```swift
// BAD: items came from a sorted source
let sorted = items.sorted(by: { $0.sortOrder < $1.sortOrder })
```

### 5. Full rebuild when targeted mutation suffices

Rebuilding an entire data structure after changing one element.

```swift
// BAD: O(n) tree traversal after changing one field
block.content = newText
reload()

// GOOD: mutate in place — no structural change, no rebuild needed
block.content = newText
```

### 6. Recursive tree walk when flat list scan works

Walking parent-child relationships recursively when the flat list already encodes the
hierarchy through indent levels or contiguous ordering.

```swift
// BAD: O(d) recursive walk, each step touches DB relationship
func collectIds(_ block: Block) {
    for child in block.children { ids.insert(child.id); collectIds(child) }
}

// GOOD: O(k) scan of contiguous entries
var end = index + 1
while end < entries.count && entries[end].indentLevel > entries[index].indentLevel {
    end += 1
}
entries.removeSubrange(index..<end)
```

### 7. Reassigning all elements when one change suffices

Updating every element's property when only the new element needs a value.

```swift
// BAD: O(n) — rewrites all siblings' sortOrders
for (i, sibling) in siblings.enumerated() {
    sibling.sortOrder = Double(i + 1)
}

// GOOD: O(1) — fractional indexing, only set the new element's sortOrder
newBlock.sortOrder = (prev.sortOrder + next.sortOrder) / 2.0
```

## What NOT to Flag

- Operations that are inherently O(n) with no way to reduce (e.g., `reload()` must traverse the tree)
- Cold paths called once at init, not on every user action
- Micro-optimizations that hurt readability for negligible gain (e.g., replacing `filter` with a manual loop to save one allocation on a 3-element array)
- Complexity bounded by small constants (e.g., max 5 depth levels)

## Severity Guide

| Complexity | On Hot Path? | Severity |
|---|---|---|
| O(n²) or worse | Yes | Fix immediately |
| O(n²) or worse | No | Flag, fix if easy |
| O(n) cold (DB) when O(k) hot exists | Yes | Fix — this is the most common win |
| O(n log n) unnecessary sort | Yes | Fix |
| O(n) full rebuild for O(1) change | Yes | Fix |
| O(n) hot, unavoidable | — | Don't flag |
