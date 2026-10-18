import Foundation

public enum MatchMode: String, CaseIterable, Identifiable, Sendable {
    case smartNumber = "Smart Number / Suffix (e.g. 8024 matches _DSC8024.JPG)"
    case exactName = "Exact Filename (e.g. DSC8024.JPG or DSC8024)"
    case contains = "Contains Text Anywhere"

    public var id: String { rawValue }
}

public struct SelectionMatchResult: Sendable {
    public let matchedItems: [DriveItem]
    public let matchedIds: Set<String>
    public let totalCandidateFiles: Int
    public let notFoundTokens: [String]
    public let totalMatchedBytes: Int64

    public var matchedCount: Int { matchedItems.count }
}

public enum SelectionMatcher {
    /// Extracts tokens from any format: comma-separated, newline-separated, spaces, tabs, semicolons
    public static func parseTokens(from input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ",\n\r\t; \t")
        var seen = Set<String>()
        var tokens: [String] = []

        let rawTokens = trimmed.components(separatedBy: separators)
        for raw in rawTokens {
            // Strip quotes, brackets, hashes, or common punctuation
            var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"\'[]()#*-:,"))
            guard !clean.isEmpty else { continue }
            let lower = clean.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                tokens.append(clean)
            }
        }
        return tokens
    }

    /// Evaluates if a single file matches a single token based on the selected mode
    public static func matches(fileName: String, token: String, mode: MatchMode) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return false }

        let fn = fileName.lowercased()
        let stem = (fileName as NSString).deletingPathExtension.lowercased()

        switch mode {
        case .exactName:
            return fn == t || stem == t

        case .smartNumber:
            // 1. Exact match with or without extension
            if fn == t || stem == t { return true }

            // 2. Stem ends with token (e.g. _DSC8024 or IMG_8024 ends with 8024)
            if stem.hasSuffix(t) { return true }

            // 3. Delimited numeric chunk: e.g. stem has _8024_ or -8024- or 8024
            if stem.contains("_\(t)") || stem.contains("-\(t)") || stem.contains(" \(t)") {
                return true
            }

            // 4. If token is numeric (e.g. "8024"), check if the digits appear inside filename
            let isNumeric = !t.isEmpty && t.allSatisfy { $0.isNumber }
            if isNumeric && stem.contains(t) {
                return true
            }

            // 5. Fallback contains
            return stem.contains(t)

        case .contains:
            return fn.contains(t)
        }
    }

    /// Evaluates all files in a folder tree against the token list
    public static func evaluate(
        tokens: [String],
        items: [DriveItem],
        mode: MatchMode
    ) -> SelectionMatchResult {
        var matchedItems: [DriveItem] = []
        var matchedIds = Set<String>()
        var notFoundTokens: [String] = []

        // Flatten all files
        let allFiles = items.flatMap { $0.flattenFiles() }

        // Test which tokens found at least 1 match
        for token in tokens {
            var foundAnyForToken = false
            for file in allFiles {
                if matches(fileName: file.name, token: token, mode: mode) {
                    foundAnyForToken = true
                    if !matchedIds.contains(file.id) {
                        matchedIds.insert(file.id)
                        matchedItems.append(file)
                    }
                }
            }
            if !foundAnyForToken {
                notFoundTokens.append(token)
            }
        }

        let totalBytes = matchedItems.reduce(0) { $0 + $1.size }

        return SelectionMatchResult(
            matchedItems: matchedItems,
            matchedIds: matchedIds,
            totalCandidateFiles: allFiles.count,
            notFoundTokens: notFoundTokens,
            totalMatchedBytes: totalBytes
        )
    }

    /// Recursively updates isSelected state in the folder tree
    public static func applySelection(
        matchedIds: Set<String>,
        rootItem: inout DriveItem,
        selectMatchedOnly: Bool
    ) {
        func updateNode(item: inout DriveItem) {
            if item.isFolder {
                if var children = item.children {
                    for i in 0..<children.count {
                        updateNode(item: &children[i])
                    }
                    item.children = children
                    item.isSelected = children.contains { $0.isSelected }
                }
            } else {
                if selectMatchedOnly {
                    item.isSelected = matchedIds.contains(item.id)
                } else {
                    if matchedIds.contains(item.id) {
                        item.isSelected = true
                    }
                }
            }
        }

        updateNode(item: &rootItem)
    }
}
