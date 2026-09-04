import Foundation

/// Turns written or recognised text into comparable tokens.
///
/// Both the script and the live transcript pass through the same normaliser so that
/// "Q4's" and "q4s", "e-mail" and "email", "20%" and "20 percent" have a fighting chance
/// of lining up.
public enum TextNormalizer {
    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20",
        "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
        "eighty": "80", "ninety": "90", "hundred": "100", "thousand": "1000",
    ]

    private static let contractions: [String: [String]] = [
        "im": ["i", "am"], "ive": ["i", "have"], "ill": ["i", "will"], "id": ["i", "would"],
        "youre": ["you", "are"], "youve": ["you", "have"], "youll": ["you", "will"],
        "were": ["we", "are"], "weve": ["we", "have"], "well": ["we", "will"],
        "theyre": ["they", "are"], "theyve": ["they", "have"], "theyll": ["they", "will"],
        "its": ["it", "is"], "thats": ["that", "is"], "whats": ["what", "is"],
        "heres": ["here", "is"], "theres": ["there", "is"], "wheres": ["where", "is"],
        "isnt": ["is", "not"], "arent": ["are", "not"], "wasnt": ["was", "not"],
        "werent": ["were", "not"], "dont": ["do", "not"], "doesnt": ["does", "not"],
        "didnt": ["did", "not"], "cant": ["can", "not"], "couldnt": ["could", "not"],
        "wont": ["will", "not"], "wouldnt": ["would", "not"], "shouldnt": ["should", "not"],
        "havent": ["have", "not"], "hasnt": ["has", "not"], "hadnt": ["had", "not"],
        "lets": ["let", "us"],
    ]

    /// Normalise one written token. Returns an empty string for pure punctuation.
    public static func normalize(_ token: String) -> String {
        var s = token.lowercased()
        s = s.replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: "%", with: " percent")
        // Keep letters, digits and internal apostrophes/hyphens; drop everything else.
        s = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "'" || $0 == "-" || $0 == " " })
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingOccurrences(of: "-", with: "")
        s = s.trimmingCharacters(in: .whitespaces)
        if let digits = numberWords[s] { return digits }
        return s
    }

    /// Normalise a run of text into match tokens, expanding common contractions so that a
    /// speaker saying "we have" still matches a script that says "we've" (and vice versa).
    public static func tokens(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .flatMap { raw -> [String] in
                let n = normalize(String(raw))
                if n.isEmpty { return [] }
                // "20 percent" arrives as one token with an inner space after normalize().
                let parts = n.split(separator: " ").map(String.init)
                return parts.flatMap { contractions[$0] ?? [$0] }
            }
    }

    /// Words a listener would not notice missing. Matching treats them as cheap to skip.
    public static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "so", "okay", "ok", "right", "basically", "actually",
        "literally", "you", "know", "kind", "of", "sort",
    ]

    public static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "with",
        "is", "are", "was", "were", "be", "it", "that", "this", "we", "i", "you", "they",
        "as", "by", "from", "so", "if", "not",
    ]
}
