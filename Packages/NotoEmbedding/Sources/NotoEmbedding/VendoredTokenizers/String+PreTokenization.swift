//
//  Vendored from https://github.com/huggingface/swift-transformers (Sources/Tokenizers/String+PreTokenization.swift)
//  Tag: 1.3.3, commit 2fa33e1f5e7131a7fc64c28e6d161dcec0d24820. License: Apache-2.0.
//  See VendoredTokenizers/LICENSE-NOTICE.md.
//  Local modifications: removed `import struct Hub.Config`;
//  StringSplitPattern compiles its regex once and splits via NSRegularExpression
//  over UTF-16 ranges (String.range(of:options:.regularExpression) rounds matches
//  to grapheme-cluster boundaries, breaking splits inside clusters such as the
//  keycap emoji, where HF splits between the digit and the combining marks).
//
import Foundation


enum StringSplitPattern {
    case regexp(regexp: NSRegularExpression)
    case string(pattern: String)

    func split(_ text: String, invert: Bool = true) -> [String] {
        switch self {
        case let .regexp(regexp):
            text.splitIsolated(by: regexp)
        case let .string(substring):
            text.split(by: substring, options: [], includeSeparators: !invert)
        }
    }

    static func from(config: Config) -> StringSplitPattern? {
        if let pattern = config.pattern.String.string() {
            return .string(pattern: pattern)
        }
        if let pattern = config.pattern.Regex.string() {
            guard let regexp = try? NSRegularExpression(pattern: pattern) else {
                fatalError("Cannot build regexp from \(pattern)")
            }
            return .regexp(regexp: regexp)
        }
        return nil
    }
}

enum SplitDelimiterBehavior {
    case removed
    case isolated
    case mergedWithPrevious
    case mergedWithNext
}

extension String {
    func ranges(of string: String, options: CompareOptions = .regularExpression) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var start = startIndex
        while let range = range(of: string, options: options, range: start..<endIndex) {
            result.append(range)
            start = range.lowerBound < range.upperBound ? range.upperBound : index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }

    func split(by string: String, options: CompareOptions = .regularExpression, includeSeparators: Bool = false, omittingEmptySubsequences: Bool = true) -> [String] {
        var result: [String] = []
        var start = startIndex
        while let range = range(of: string, options: options, range: start..<endIndex) {
            // Prevent empty strings
            if omittingEmptySubsequences, start < range.lowerBound {
                result.append(String(self[start..<range.lowerBound]))
            }
            if includeSeparators {
                result.append(String(self[range]))
            }
            start = range.upperBound
        }

        if omittingEmptySubsequences, start < endIndex {
            result.append(String(self[start...]))
        }
        return result
    }

    /// This version supports capture groups, wheres the one above doesn't
    func split(by captureRegex: NSRegularExpression) -> [String] {
        // Find the matching capture groups
        let selfRange = NSRange(startIndex..<endIndex, in: self)
        let matches = captureRegex.matches(in: self, options: [], range: selfRange)

        if matches.isEmpty { return [self] }

        var result: [String] = []
        var start = startIndex

        for match in matches {
            // IMPORTANT: convert from NSRange to Range<String.Index>
            // https://stackoverflow.com/questions/75543272/convert-a-given-utf8-nsrange-in-a-string-to-a-utf16-nsrange
            guard let matchRange = Range(match.range, in: self) else { continue }

            // Add text before the match
            if start < matchRange.lowerBound {
                result.append(String(self[start..<matchRange.lowerBound]))
            }

            // Move start to after the match
            start = matchRange.upperBound

            // Append separator, supporting capture groups
            for r in (0..<match.numberOfRanges).reversed() {
                let nsRange = match.range(at: r)
                if let sepRange = Range(nsRange, in: self) {
                    result.append(String(self[sepRange]))
                    break
                }
            }
        }

        // Append remaining suffix
        if start < endIndex {
            result.append(String(self[start...]))
        }

        return result
    }

    func split(by string: String, options: CompareOptions = .regularExpression, behavior: SplitDelimiterBehavior) -> [String] {
        func mergedWithNext(ranges: [Range<String.Index>]) -> [Range<String.Index>] {
            var merged: [Range<String.Index>] = []
            var currentStart = startIndex
            for range in ranges {
                if range.lowerBound == startIndex { continue }
                let mergedRange = currentStart..<range.lowerBound
                currentStart = range.lowerBound
                merged.append(mergedRange)
            }
            if currentStart < endIndex {
                merged.append(currentStart..<endIndex)
            }
            return merged
        }

        func mergedWithPrevious(ranges: [Range<String.Index>]) -> [Range<String.Index>] {
            var merged: [Range<String.Index>] = []
            var currentStart = startIndex
            for range in ranges {
                let mergedRange = currentStart..<range.upperBound
                currentStart = range.upperBound
                merged.append(mergedRange)
            }
            if currentStart < endIndex {
                merged.append(currentStart..<endIndex)
            }
            return merged
        }

        switch behavior {
        case .removed:
            return split(by: string, options: options, includeSeparators: false)
        case .isolated:
            return split(by: string, options: options, includeSeparators: true)
        case .mergedWithNext:
            // Obtain ranges and merge them
            // "the-final--countdown" -> (3, 4), (9, 10), (10, 11) -> (start, 2), (3, 8), (9, 9), (10, end)
            let ranges = ranges(of: string, options: options)
            let merged = mergedWithNext(ranges: ranges)
            return merged.map { String(self[$0]) }
        case .mergedWithPrevious:
            // Obtain ranges and merge them
            // "the-final--countdown" -> (3, 4), (9, 10), (10, 11) -> (start, 3), (4, 9), (10, 10), (11, end)
            let ranges = ranges(of: string, options: options)
            let merged = mergedWithPrevious(ranges: ranges)
            return merged.map { String(self[$0]) }
        }
    }
}

extension String {
    /// Split with `Isolated` delimiter behavior using exact UTF-16 match ranges.
    ///
    /// `range(of:options:.regularExpression)` rounds match ranges outward to
    /// grapheme-cluster boundaries, which corrupts patterns that must split
    /// inside a cluster (e.g. the o200k split regex matching `1` inside the
    /// keycap emoji `1\u{FE0F}\u{20E3}`). `NSRegularExpression` +
    /// `NSString.substring` operate on UTF-16 code units and preserve the
    /// exact boundaries the reference Rust `tokenizers` implementation uses.
    func splitIsolated(by regex: NSRegularExpression) -> [String] {
        let nsText = self as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: [String] = []
        var start = 0
        regex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match, match.range.length > 0 else { return }
            if match.range.location > start {
                result.append(nsText.substring(with: NSRange(location: start, length: match.range.location - start)))
            }
            result.append(nsText.substring(with: match.range))
            start = match.range.location + match.range.length
        }
        if start < nsText.length {
            result.append(nsText.substring(from: start))
        }
        return result
    }
}
