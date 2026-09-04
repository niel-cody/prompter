import Foundation

/// Splits a script into natural spoken phrases.
///
/// The parser is deliberately rule-based and local: punctuation, clause boundaries, and
/// a breath-length budget. It is good enough to make the prompt feel natural, and its
/// output is the same `PresentationScript` an AI-backed optimiser could produce later.
public struct PhraseParser: Sendable {
    public struct Options: Sendable {
        /// Phrases longer than this are split at the best clause boundary.
        public var maxWordsPerPhrase: Int = 11
        /// Fragments shorter than this are merged with a neighbour unless they stand alone
        /// as a sentence.
        public var minWordsPerPhrase: Int = 3
        /// A standalone sentence of at most this many words is treated as emphatic.
        public var emphaticSentenceMaxWords: Int = 5

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func parse(_ text: String) -> PresentationScript {
        var phrases: [Phrase] = []
        var sections: [Section] = []
        var sentenceCounter = 0

        for (sectionIndex, paragraph) in paragraphs(in: text).enumerated() {
            let sectionStart = phrases.count
            let sentences = self.sentences(in: paragraph)

            for (sentenceOrdinal, sentence) in sentences.enumerated() {
                let sentenceIndex = sentenceCounter
                sentenceCounter += 1
                let isLastSentence = sentenceOrdinal == sentences.count - 1
                let isOpener = sectionIndex == 0 && sentenceOrdinal == 0
                let isShortStandalone = sentences.count > 1 && !isOpener
                    && wordCount(sentence) <= options.emphaticSentenceMaxWords
                let emphasis: Emphasis = (isShortStandalone || sentence.hasSuffix("!")) ? .strong : .normal

                let fragments = clauses(in: sentence)
                for (i, fragment) in fragments.enumerated() {
                    let isLast = i == fragments.count - 1
                    var pause: PauseKind
                    if isLast {
                        pause = isLastSentence ? .paragraph : .sentence
                        if emphasis == .strong, !isLastSentence { pause = .emphatic }
                    } else {
                        pause = fragment.pauseAfter
                    }
                    let words = tokenize(fragment.text)
                    guard !words.isEmpty else { continue }
                    phrases.append(Phrase(
                        id: phrases.count,
                        text: fragment.text,
                        words: words,
                        sectionIndex: sectionIndex,
                        sentenceIndex: sentenceIndex,
                        isSentenceStart: i == 0,
                        isSentenceEnd: isLast,
                        pauseAfter: pause,
                        emphasis: emphasis
                    ))
                }
            }

            if phrases.count > sectionStart {
                sections.append(Section(index: sections.count, phraseRange: sectionStart..<phrases.count))
            }
        }

        // A strong statement deserves a breath before it, not just after.
        phrases = phrases.enumerated().map { index, phrase in
            guard index + 1 < phrases.count,
                  phrases[index + 1].emphasis == .strong,
                  phrases[index + 1].isSentenceStart,
                  phrase.pauseAfter < .emphatic
            else { return phrase }
            return phrase.replacingPause(.emphatic)
        }

        return PresentationScript(sourceText: text, sections: sections, phrases: phrases)
    }

    // MARK: - Paragraphs

    func paragraphs(in text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map(stripMarkdown)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Light-touch Markdown removal: headings, bullets, emphasis markers, links.
    func stripMarkdown(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*([-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__|\*|_|`)"#, with: "", options: .regularExpression)
        return s
    }

    // MARK: - Sentences

    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "eg", "ie", "no", "inc", "ltd", "co", "approx",
    ]

    func sentences(in paragraph: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(paragraph)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if c == "." || c == "!" || c == "?" || c == "…" {
                // Swallow runs like "?!" or "..." and a closing quote/bracket.
                var j = i + 1
                while j < chars.count, ".!?…\"'”’)".contains(chars[j]) {
                    current.append(chars[j])
                    j += 1
                }
                let atEnd = j >= chars.count
                let followedBySpace = !atEnd && chars[j].isWhitespace
                if atEnd || followedBySpace, !isAbbreviationEnding(current), !isDecimalPoint(chars, at: i) {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
                i = j
                continue
            }
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private func isAbbreviationEnding(_ s: String) -> Bool {
        guard s.hasSuffix(".") else { return false }
        let lastWord = s.dropLast().split(separator: " ").last.map(String.init) ?? ""
        let cleaned = lastWord.lowercased().filter(\.isLetter)
        if Self.abbreviations.contains(cleaned) { return true }
        // Single capital initial, like "J. Smith".
        return lastWord.count == 1 && lastWord.first!.isUppercase
    }

    private func isDecimalPoint(_ chars: [Character], at i: Int) -> Bool {
        guard chars[i] == ".", i > 0, i + 1 < chars.count else { return false }
        return chars[i - 1].isNumber && chars[i + 1].isNumber
    }

    // MARK: - Clauses / phrases

    struct Fragment {
        var text: String
        var pauseAfter: PauseKind
    }

    /// Words that read naturally at the start of a new line when a long clause is split.
    private static let breakBeforeWords: Set<String> = [
        "and", "but", "because", "so", "which", "that", "when", "while", "if", "then",
        "although", "though", "unless", "until", "after", "before", "where", "whereas",
        "rather", "instead", "despite", "since", "as", "or", "nor", "yet", "to", "with",
        "without", "about", "into", "through", "across", "than", "who", "whether",
    ]

    func clauses(in sentence: String) -> [Fragment] {
        // 1. Split on punctuation that marks a clause boundary.
        var fragments: [Fragment] = []
        var current = ""
        let chars = Array(sentence)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // Spaced dashes: " - ", " – ", " — " and unspaced em dashes.
            let isDash = (c == "—" || c == "–") || (c == "-" && i > 0 && i + 1 < chars.count && chars[i - 1] == " " && chars[i + 1] == " ")
            if isDash {
                let t = current.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { fragments.append(Fragment(text: t, pauseAfter: .clause)) }
                current = ""
                i += 1
                continue
            }
            current.append(c)
            let isComma = c == ","
            let isColonLike = c == ";" || c == ":"
            let isOpenParen = c == "(" && i > 0
            let isCloseParen = c == ")" && i + 1 < chars.count
            if isComma || isColonLike || isCloseParen {
                let nextIsSpaceOrEnd = i + 1 >= chars.count || chars[i + 1].isWhitespace
                let isThousandsComma = isComma && i > 0 && i + 1 < chars.count && chars[i - 1].isNumber && chars[i + 1].isNumber
                if nextIsSpaceOrEnd, !isThousandsComma {
                    let t = current.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { fragments.append(Fragment(text: t, pauseAfter: isComma ? .beat : .clause)) }
                    current = ""
                }
            } else if isOpenParen {
                current.removeLast()
                let t = current.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { fragments.append(Fragment(text: t, pauseAfter: .clause)) }
                current = "("
            }
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { fragments.append(Fragment(text: tail, pauseAfter: .none)) }
        if fragments.isEmpty { return [] }
        fragments[fragments.count - 1].pauseAfter = .none

        // 2. Break anything longer than a breath at the best conjunction near the middle.
        fragments = fragments.flatMap(splitLong)

        // 3. Merge fragments too short to stand alone into their neighbour.
        return mergeShort(fragments)
    }

    private func splitLong(_ fragment: Fragment) -> [Fragment] {
        let words = fragment.text.split(separator: " ").map(String.init)
        guard words.count > options.maxWordsPerPhrase else { return [fragment] }

        let minSide = options.minWordsPerPhrase
        let candidates = (minSide...(words.count - minSide)).filter { idx in
            Self.breakBeforeWords.contains(TextNormalizer.normalize(words[idx]))
        }
        let middle = words.count / 2
        let cut: Int
        if let best = candidates.min(by: { abs($0 - middle) < abs($1 - middle) }) {
            cut = best
        } else {
            // No natural conjunction: split into roughly even halves.
            cut = middle
        }
        let head = Fragment(text: words[..<cut].joined(separator: " "), pauseAfter: .none)
        let tail = Fragment(text: words[cut...].joined(separator: " "), pauseAfter: fragment.pauseAfter)
        return splitLong(head) + splitLong(tail)
    }

    private func mergeShort(_ fragments: [Fragment]) -> [Fragment] {
        guard fragments.count > 1 else { return fragments }
        var result = fragments
        var i = 0
        while i < result.count, result.count > 1 {
            let count = wordCount(result[i].text)
            if count < options.minWordsPerPhrase {
                if i + 1 < result.count, wordCount(result[i + 1].text) + count <= options.maxWordsPerPhrase {
                    // Merge forward, keeping the later fragment's pause.
                    result[i + 1].text = result[i].text + " " + result[i + 1].text
                    result.remove(at: i)
                    continue
                } else if i > 0, wordCount(result[i - 1].text) + count <= options.maxWordsPerPhrase {
                    result[i - 1].text += " " + result[i].text
                    result[i - 1].pauseAfter = result[i].pauseAfter
                    result.remove(at: i)
                    continue
                }
            }
            i += 1
        }
        return result
    }

    // MARK: - Words

    func tokenize(_ text: String) -> [Word] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .compactMap { raw in
                let n = TextNormalizer.normalize(raw)
                return n.isEmpty ? nil : Word(text: raw, normalized: n)
            }
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }
}

private extension Phrase {
    func replacingPause(_ pause: PauseKind) -> Phrase {
        Phrase(id: id, text: text, words: words, sectionIndex: sectionIndex, sentenceIndex: sentenceIndex,
               isSentenceStart: isSentenceStart, isSentenceEnd: isSentenceEnd, pauseAfter: pause, emphasis: emphasis)
    }
}
