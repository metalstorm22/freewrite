import Foundation
import NaturalLanguage

enum StyleCategory: String, CaseIterable, Identifiable {
    case redundancy = "Redundancy"
    case style = "Style"
    case punctuation = "Punctuation"
    case typography = "Typography"
    case semantics = "Semantics"
    
    var id: String { rawValue }
}

enum StyleSeverity: String {
    case info
    case warning
}

struct StyleFix: Identifiable {
    let id = UUID()
    let range: NSRange
    let replacement: String?
    
    static func delete(range: NSRange) -> StyleFix {
        StyleFix(range: range, replacement: "")
    }
    
    static func replace(range: NSRange, with text: String) -> StyleFix {
        StyleFix(range: range, replacement: text)
    }
}

struct StyleIssue: Identifiable {
    let id = UUID()
    let category: StyleCategory
    let severity: StyleSeverity
    let range: NSRange
    let message: String
    let fix: StyleFix?
    let ignoredKey: String?
    
    init(
        category: StyleCategory,
        severity: StyleSeverity = .info,
        range: NSRange,
        message: String,
        fix: StyleFix? = nil,
        ignoredKey: String? = nil
    ) {
        self.category = category
        self.severity = severity
        self.range = range
        self.message = message
        self.fix = fix
        self.ignoredKey = ignoredKey
    }
}

final class StyleAnalyzer {
    private let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with",
        "at", "from", "by", "as", "that", "this", "it", "be", "is", "are", "was",
        "were", "i", "you", "he", "she", "we", "they", "them", "their", "our",
        "your", "my", "me", "so", "if", "then", "than", "also"
    ]
    
    private let weakIntensifiers: Set<String> = [
        "very", "really", "just", "quite", "basically", "literally", "pretty"
    ]
    
    private let hedges: [String] = [
        "i think", "kind of", "sort of", "maybe", "perhaps", "i feel like", "a bit", "a little"
    ]
    
    private let vaguePronouns: Set<String> = ["this", "that", "it", "there"]
    private let fillerNouns: Set<String> = ["thing", "stuff", "things"]
    private let expletiveStarts: [String] = [
        "there is", "there are", "it is", "it was", "it seems", "it appears", "it feels"
    ]
    private let wordyPhrases: [String: String] = [
        "in order to": "to",
        "due to the fact that": "because",
        "at this point in time": "now",
        "for the purpose of": "to"
    ]
    
    func analyze(text: String) -> [StyleIssue] {
        guard !text.isEmpty else { return [] }
        
        let sentences = sentenceRanges(in: text)
        let tokens = wordTokens(in: text)
        var issues: [StyleIssue] = []
        
        issues.append(contentsOf: redundancyIssues(in: text, tokens: tokens, sentences: sentences))
        issues.append(contentsOf: punctuationIssues(in: text))
        issues.append(contentsOf: typographyIssues(in: text))
        issues.append(contentsOf: styleIssues(in: text, sentences: sentences, tokens: tokens))
        issues.append(contentsOf: semanticIssues(in: text, sentences: sentences, tokens: tokens))
        
        return issues
    }
}

private extension StyleAnalyzer {
    struct Token {
        let text: String
        let lemma: String
        let lexicalClass: NLTag?
        let range: NSRange
    }
    
    func wordTokens(in text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let nsText = text as NSString
        
        var tokens: [Token] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: text)
            let lexTag = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass
            ).0
            
            let lemmaTag = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lemma
            ).0
            
            let tokenText = nsText.substring(with: nsRange)
            let lemmaValue = lemmaTag?.rawValue.lowercased() ?? tokenText.lowercased()
            
            tokens.append(Token(
                text: tokenText,
                lemma: lemmaValue,
                lexicalClass: lexTag,
                range: nsRange
            ))
            return true
        }
        return tokens
    }
    
    func sentenceRanges(in text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            ranges.append(NSRange(tokenRange, in: text))
            return true
        }
        return ranges
    }
    
    func redundancyIssues(in text: String, tokens: [Token], sentences: [NSRange]) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        var lastSeen: [String: Int] = [:]
        
        for (index, token) in tokens.enumerated() {
            guard !stopwords.contains(token.lemma) else { continue }
            if let previousIndex = lastSeen[token.lemma], index - previousIndex <= 35 {
                issues.append(StyleIssue(
                    category: .redundancy,
                    severity: .info,
                    range: token.range,
                    message: "Repeated word \"\(token.text)\" nearby",
                    fix: .delete(range: token.range),
                    ignoredKey: token.lemma
                ))
            }
            lastSeen[token.lemma] = index
        }
        
        // Repeated 3-grams across sentences
        var ngramMap: [String: (sentenceIndex: Int, range: NSRange)] = [:]
        let nsText = text as NSString
        
        for (index, sentenceRange) in sentences.enumerated() {
            let sentenceText = nsText.substring(with: sentenceRange)
            let sentenceTokens = wordTokens(in: sentenceText).filter {
                !$0.text.trimmingCharacters(in: .punctuationCharacters).isEmpty
            }
            
            guard sentenceTokens.count >= 3 else { continue }
            for windowStart in 0...(sentenceTokens.count - 3) {
                let slice = sentenceTokens[windowStart..<(windowStart + 3)]
                let key = slice.map { $0.lemma }.joined(separator: " ")
                let combinedRange = NSRange(
                    location: sentenceRange.location + slice.first!.range.location,
                    length: slice.last!.range.location + slice.last!.range.length - slice.first!.range.location
                )
                if let previous = ngramMap[key], index - previous.sentenceIndex <= 4 {
                    issues.append(StyleIssue(
                        category: .redundancy,
                        severity: .info,
                        range: combinedRange,
                        message: "Repeated phrase appears in nearby sentences",
                        fix: .delete(range: combinedRange),
                        ignoredKey: key
                    ))
                }
                ngramMap[key] = (index, combinedRange)
            }
        }
        
        // Echo sentences (high lemma overlap)
        for pairIndex in 1..<sentences.count {
            let currentRange = sentences[pairIndex]
            let previousRange = sentences[pairIndex - 1]
            
            let currentTokens = Set(
                tokensInRange(currentRange, from: tokens).map { $0.lemma }.filter { !$0.isEmpty && !stopwords.contains($0) }
            )
            let previousTokens = Set(
                tokensInRange(previousRange, from: tokens).map { $0.lemma }.filter { !$0.isEmpty && !stopwords.contains($0) }
            )
            
            guard !currentTokens.isEmpty, !previousTokens.isEmpty else { continue }
            let intersection = currentTokens.intersection(previousTokens)
            let union = currentTokens.union(previousTokens)
            let overlap = Double(intersection.count) / Double(union.count)
            
            if overlap >= 0.5 && intersection.count >= 4 {
                issues.append(StyleIssue(
                    category: .redundancy,
                    severity: .info,
                    range: currentRange,
                    message: "This sentence echoes the previous one",
                    fix: nil,
                    ignoredKey: nil
                ))
            }
        }
        
        return issues
    }
    
    func styleIssues(in text: String, sentences: [NSRange], tokens: [Token]) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        let nsText = text as NSString
        var lastSentenceStart: String?
        var repeatedStartCount = 0
        
        // Adverb pile-up + weak intensifiers
        for sentenceRange in sentences {
            let sentenceTokens = tokensInRange(sentenceRange, from: tokens)
            let adverbs = sentenceTokens.filter { $0.lexicalClass == NLTag.adverb }
            let wordCount = max(1, sentenceTokens.count)
            let adverbRatio = Double(adverbs.count) / Double(wordCount)
            
            if adverbs.count >= 4 || adverbRatio > 0.28 {
                issues.append(StyleIssue(
                    category: .style,
                    severity: .info,
                    range: sentenceRange,
                    message: "Adverb heavy sentence; tighten the verb",
                    fix: nil,
                    ignoredKey: nil
                ))
            }
            
            for token in sentenceTokens where weakIntensifiers.contains(token.lemma) {
                issues.append(StyleIssue(
                    category: .style,
                    severity: .info,
                    range: token.range,
                    message: "Weak intensifier \"\(token.text)\"",
                    fix: .delete(range: token.range),
                    ignoredKey: token.lemma
                ))
            }
            
            // Expletive openings ("there is", "it is...")
            let sentenceText = nsText.substring(with: sentenceRange).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let opener = expletiveStarts.first(where: { sentenceText.hasPrefix($0) }) {
                issues.append(StyleIssue(
                    category: .style,
                    severity: .info,
                    range: sentenceRange,
                    message: "Weak opener \"\(opener)\"; make the subject concrete",
                    fix: nil,
                    ignoredKey: opener
                ))
            }
            
            // Wordy phrases inside the sentence
            for (wordy, replacement) in wordyPhrases {
                var searchRange = sentenceText.startIndex..<sentenceText.endIndex
                while let found = sentenceText.range(of: wordy, options: [], range: searchRange) {
                    let localRange = NSRange(found, in: sentenceText)
                    let globalRange = NSRange(location: sentenceRange.location + localRange.location, length: localRange.length)
                    issues.append(StyleIssue(
                        category: .style,
                        severity: .info,
                        range: globalRange,
                        message: "Wordy phrase \"\(wordy)\"",
                        fix: .replace(range: globalRange, with: replacement),
                        ignoredKey: wordy
                    ))
                    searchRange = found.upperBound..<sentenceText.endIndex
                }
            }
            
            // Repeated sentence starts
            if let firstContent = sentenceTokens.first(where: { !stopwords.contains($0.lemma) })?.lemma {
                if firstContent == lastSentenceStart {
                    repeatedStartCount += 1
                } else {
                    repeatedStartCount = 0
                }
                lastSentenceStart = firstContent
                
                if repeatedStartCount >= 2 {
                    issues.append(StyleIssue(
                        category: .style,
                        severity: .info,
                        range: sentenceRange,
                        message: "Several sentences start with \"\(firstContent)\"; vary the openings",
                        fix: nil,
                        ignoredKey: "start:\(firstContent)"
                    ))
                }
            }
            
            // Long sentence heuristic
            if wordCount > 40 {
                issues.append(StyleIssue(
                    category: .style,
                    severity: .warning,
                    range: sentenceRange,
                    message: "Long sentence; consider splitting",
                    fix: nil,
                    ignoredKey: nil
                ))
            }
        }
        
        // Hedges
        let lowered = text.lowercased()
        for phrase in hedges {
            var searchRange = lowered.startIndex..<lowered.endIndex
            while let foundRange = lowered.range(of: phrase, options: [], range: searchRange) {
                let nsRange = NSRange(foundRange, in: lowered)
                issues.append(StyleIssue(
                    category: .style,
                    severity: .info,
                    range: nsRange,
                    message: "Hedging phrase \"\(phrase)\"",
                    fix: .delete(range: nsRange),
                    ignoredKey: phrase
                ))
                searchRange = foundRange.upperBound..<lowered.endIndex
            }
        }
        
        // Overuse of filler nouns
        for token in tokens where fillerNouns.contains(token.lemma) {
            issues.append(StyleIssue(
                category: .style,
                severity: .info,
                range: token.range,
                message: "Be specific instead of \"\(token.text)\"",
                fix: nil,
                ignoredKey: token.lemma
            ))
        }
        
        return issues
    }
    
    func punctuationIssues(in text: String) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        let patterns: [(String, String, String)] = [
            ("Multiple spaces", " {2,}", " "),
            ("Space before punctuation", "\\s+([,.;:!?])", "$1"),
            ("Multiple exclamation/question marks", "([!?]){2,}", "$1"),
            ("Lowercase after sentence end", "([.!?]\\s+)([a-z])", "$1\u{00A7}")
        ]
        
        for (message, pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
                for match in matches {
                    let range = match.range
                    let fixReplacement: String?
                    if replacement == "$1\u{00A7}" {
                        // Special-case: capitalize the second capture group
                        if match.numberOfRanges >= 3 {
                            let nsText = text as NSString
                            let prefix = nsText.substring(with: match.range(at: 1))
                            let letter = nsText.substring(with: match.range(at: 2)).capitalized
                            fixReplacement = prefix + letter
                        } else {
                            fixReplacement = nil
                        }
                    } else {
                        fixReplacement = regex.replacementString(for: match, in: text, offset: 0, template: replacement)
                    }
                    
                    issues.append(StyleIssue(
                        category: .punctuation,
                        severity: .info,
                        range: range,
                        message: message,
                        fix: fixReplacement != nil ? .replace(range: range, with: fixReplacement!) : nil,
                        ignoredKey: nil
                    ))
                }
            }
        }
        
        // Unmatched quotes or parentheses (odd counts)
        let quoteChar: Character = "\""
        let quoteCount = text.filter { $0 == quoteChar }.count
        if quoteCount % 2 != 0, let lastIndex = text.lastIndex(of: quoteChar) {
            let nsRange = NSRange(lastIndex..<text.index(after: lastIndex), in: text)
            issues.append(StyleIssue(
                category: .punctuation,
                severity: .info,
                range: nsRange,
                message: "Unmatched quote",
                fix: nil,
                ignoredKey: nil
            ))
        }
        
        let openParen: Character = "("
        let closeParen: Character = ")"
        let openParens = text.filter { $0 == openParen }.count
        let closeParens = text.filter { $0 == closeParen }.count
        if openParens != closeParens,
           let lastIndex = text.lastIndex(of: openParens > closeParens ? openParen : closeParen) {
            let nsRange = NSRange(lastIndex..<text.index(after: lastIndex), in: text)
            issues.append(StyleIssue(
                category: .punctuation,
                severity: .info,
                range: nsRange,
                message: "Unmatched parenthesis",
                fix: nil,
                ignoredKey: nil
            ))
        }
        
        return issues
    }
    
    func typographyIssues(in text: String) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        if let doubleDashRegex = try? NSRegularExpression(pattern: "--") {
            let matches = doubleDashRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            for match in matches {
                issues.append(StyleIssue(
                    category: .typography,
                    severity: .info,
                    range: match.range,
                    message: "Use an em dash",
                    fix: .replace(range: match.range, with: "—"),
                    ignoredKey: nil
                ))
            }
        }
        
        if let ellipsisRegex = try? NSRegularExpression(pattern: "\\.{3,}") {
            let matches = ellipsisRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            for match in matches {
                issues.append(StyleIssue(
                    category: .typography,
                    severity: .info,
                    range: match.range,
                    message: "Use a single ellipsis",
                    fix: .replace(range: match.range, with: "…"),
                    ignoredKey: nil
                ))
            }
        }
        
        return issues
    }
    
    func semanticIssues(in text: String, sentences: [NSRange], tokens: [Token]) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        let paragraphs = (text as NSString).components(separatedBy: "\n\n")
        var paragraphStartLocation = 0
        
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                paragraphStartLocation += paragraph.count + 2
                continue
            }
            
            let nsParagraph = paragraph as NSString
            let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            if let firstWord = words.first {
                let lower = firstWord.lowercased()
                if vaguePronouns.contains(lower) {
                    // Check for noun presence nearby
                    let nearbyTokens = tokens.filter { token in
                        token.range.location >= paragraphStartLocation &&
                        token.range.location < paragraphStartLocation + min(paragraph.count, 120)
                    }
                    let hasNoun = nearbyTokens.contains { token in
                        guard let tag = token.lexicalClass else { return false }
                        return tag == .noun
                    }
                    if !hasNoun {
                        let nsRange = nsParagraph.range(of: String(firstWord))
                        if nsRange.location != NSNotFound {
                            let range = NSRange(
                                location: paragraphStartLocation + nsRange.location,
                                length: nsRange.length
                            )
                            issues.append(StyleIssue(
                                category: .semantics,
                                severity: .info,
                                range: range,
                                message: "Unclear reference at paragraph start",
                                fix: nil,
                                ignoredKey: lower
                            ))
                        }
                    }
                }
            }
            
            paragraphStartLocation += paragraph.count + 2
        }
        
        // Vague "thing/stuff" frequency
        let fillerCount = tokens.filter { fillerNouns.contains($0.lemma) }.count
        if fillerCount >= 3, let first = tokens.first(where: { fillerNouns.contains($0.lemma) }) {
            issues.append(StyleIssue(
                category: .semantics,
                severity: .info,
                range: first.range,
                message: "Frequent vague nouns; add specifics",
                fix: nil,
                ignoredKey: "filler"
            ))
        }
        
        return issues
    }
    
    func tokensInRange(_ range: NSRange, from tokens: [Token]) -> [Token] {
        tokens.filter { token in
            NSIntersectionRange(token.range, range).length > 0
        }
    }
}
