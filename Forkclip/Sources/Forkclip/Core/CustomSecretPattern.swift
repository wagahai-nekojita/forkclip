import Foundation

struct CustomSecretPattern: Codable, Equatable, Sendable {
    let name: String
    let pattern: String
}

enum CustomSecretPatternValidationError: Error, Equatable, Sendable {
    case emptyName
    case emptyPattern
    case patternTooLong
    case invalidRegex
    case matchesEmptyString
    case tooBroad(String)
}

enum CustomSecretPatternValidator {
    static let maximumPatternLength = 240

    private static let broadMatchSamples = [
        "hello",
        "https://example.com/docs/reference",
        "this is a regular sentence for clipboard history",
        "今日の認証コードについてのドキュメントを更新する"
    ]

    static func validated(_ pattern: CustomSecretPattern) throws -> CustomSecretPattern {
        let normalized = CustomSecretPattern(
            name: pattern.name.trimmingCharacters(in: .whitespacesAndNewlines),
            pattern: pattern.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !normalized.name.isEmpty else {
            throw CustomSecretPatternValidationError.emptyName
        }
        guard !normalized.pattern.isEmpty else {
            throw CustomSecretPatternValidationError.emptyPattern
        }
        guard normalized.pattern.count <= maximumPatternLength else {
            throw CustomSecretPatternValidationError.patternTooLong
        }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: normalized.pattern)
        } catch {
            throw CustomSecretPatternValidationError.invalidRegex
        }

        guard firstMatch(in: "", regex: regex) == nil else {
            throw CustomSecretPatternValidationError.matchesEmptyString
        }

        for sample in broadMatchSamples where firstMatch(in: sample, regex: regex) != nil {
            throw CustomSecretPatternValidationError.tooBroad(sample)
        }

        return normalized
    }

    static func compiledRegexes(for patterns: [CustomSecretPattern]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0.pattern) }
    }

    static func firstMatch(in text: String, regex: NSRegularExpression) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

enum CustomSecretPatternStore {
    static func load(from url: URL) throws -> [CustomSecretPattern] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        let patterns = try JSONDecoder().decode([CustomSecretPattern].self, from: data)
        return try patterns.map(CustomSecretPatternValidator.validated)
    }

    static func save(_ patterns: [CustomSecretPattern], to url: URL) throws {
        let validatedPatterns = try patterns.map(CustomSecretPatternValidator.validated)
        try AppPaths.createOwnerOnlyDirectory(at: url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validatedPatterns)
        try data.write(to: url, options: .atomic)
        try AppPaths.applyOwnerOnlyFilePermissions(to: url)
    }
}
