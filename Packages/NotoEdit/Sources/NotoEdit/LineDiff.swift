import Foundation

/// Minimal LCS-based line differ. Produces an ordered list of diff rows for a
/// small changed region: unchanged lines become `.context`, removed lines
/// `.removed`, added lines `.added`. Region sizes are tiny (a hunk), so the
/// O(n·m) table is fine.
enum LineDiff {
    static func diff(before: [String], after: [String]) -> [DiffLine] {
        let n = before.count
        let m = after.count
        if n == 0 { return after.map { DiffLine(kind: .added, text: $0) } }
        if m == 0 { return before.map { DiffLine(kind: .removed, text: $0) } }

        // LCS length table.
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if before[i] == after[j] {
                    lcs[i][j] = lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        // Backtrack into an ordered row list. Removals are emitted before
        // additions at the same divergence point (red − above green +).
        var rows: [DiffLine] = []
        var i = 0
        var j = 0
        while i < n && j < m {
            if before[i] == after[j] {
                rows.append(DiffLine(kind: .context, text: before[i]))
                i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                rows.append(DiffLine(kind: .removed, text: before[i]))
                i += 1
            } else {
                rows.append(DiffLine(kind: .added, text: after[j]))
                j += 1
            }
        }
        while i < n { rows.append(DiffLine(kind: .removed, text: before[i])); i += 1 }
        while j < m { rows.append(DiffLine(kind: .added, text: after[j])); j += 1 }
        return rows
    }
}
