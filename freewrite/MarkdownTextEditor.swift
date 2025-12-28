import AppKit
import SwiftUI

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let backgroundColor: NSColor
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        context.coordinator.configure(textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.updateParent(self)
        context.coordinator.updateConfig(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme
        )

        textView.backgroundColor = backgroundColor
        nsView.backgroundColor = backgroundColor

        if textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }

        context.coordinator.applyHighlighting(to: textView)
    }
}

class MarkdownTextEditorCoordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    private let highlighter = MarkdownHighlighter()
    private var config = MarkdownStyleConfig.defaultConfig()
    var isUpdating = false

    func updateConfig(
        fontName: String,
        fontSize: CGFloat,
        textColor: NSColor,
        backgroundColor: NSColor,
        lineSpacing: CGFloat,
        colorScheme: ColorScheme
    ) {
        config = MarkdownStyleConfig(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme
        )
    }

    func configure(textView: NSTextView) {
        textView.string = ""
        textView.insertionPointColor = config.textColor
        applyHighlighting(to: textView)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard !isUpdating else { return }
        isUpdating = true
        applyHighlighting(to: textView)
        isUpdating = false
    }

    func applyHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let selectedRanges = textView.selectedRanges
        let activeRange = activeLineRange(for: textView)
        highlighter.apply(to: textStorage, config: config, activeRange: activeRange)
        textView.insertionPointColor = config.textColor
        textView.typingAttributes = [
            .font: config.baseFont,
            .foregroundColor: config.textColor,
            .paragraphStyle: config.paragraphStyle
        ]
        textView.selectedRanges = selectedRanges
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard !isUpdating else { return }
        isUpdating = true
        applyHighlighting(to: textView)
        isUpdating = false
    }

    private func activeLineRange(for textView: NSTextView) -> NSRange? {
        guard let selectionValue = textView.selectedRanges.first as? NSValue else { return nil }
        let selectionRange = selectionValue.rangeValue
        guard selectionRange.location != NSNotFound else { return nil }
        let text = textView.string as NSString
        if text.length == 0 {
            return nil
        }
        let boundedLocation = min(selectionRange.location, max(0, text.length - 1))
        let adjustedRange = NSRange(location: boundedLocation, length: selectionRange.length)
        return text.lineRange(for: adjustedRange)
    }
}

private struct MarkdownStyleConfig {
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let backgroundColor: NSColor
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme

    var baseFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    var tokenColor: NSColor {
        textColor.withAlphaComponent(colorScheme == .dark ? 0.45 : 0.35)
    }

    var hiddenTokenColor: NSColor {
        backgroundColor
    }

    var hiddenTokenFont: NSFont {
        let size = max(0.1, fontSize * 0.05)
        return NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }

    var mutedTextColor: NSColor {
        textColor.withAlphaComponent(colorScheme == .dark ? 0.6 : 0.65)
    }

    var linkColor: NSColor {
        colorScheme == .dark ? NSColor.systemTeal : NSColor.systemBlue
    }

    var markBackground: NSColor {
        (colorScheme == .dark ? NSColor.systemYellow : NSColor.systemYellow)
            .withAlphaComponent(colorScheme == .dark ? 0.25 : 0.18)
    }

    var annotationBackground: NSColor {
        (colorScheme == .dark ? NSColor.systemTeal : NSColor.systemBlue)
            .withAlphaComponent(colorScheme == .dark ? 0.2 : 0.15)
    }

    var commentBackground: NSColor {
        (colorScheme == .dark ? NSColor.systemOrange : NSColor.systemOrange)
            .withAlphaComponent(colorScheme == .dark ? 0.2 : 0.12)
    }

    var codeBackground: NSColor {
        (colorScheme == .dark ? NSColor.systemGray : NSColor.systemGray)
            .withAlphaComponent(colorScheme == .dark ? 0.3 : 0.16)
    }

    var codeColor: NSColor {
        colorScheme == .dark ? NSColor.systemOrange : NSColor.systemBrown
    }

    var deletionColor: NSColor {
        colorScheme == .dark ? NSColor.systemRed : NSColor.systemRed
    }

    var quoteColor: NSColor {
        colorScheme == .dark ? NSColor.systemTeal : NSColor.systemBlue
    }

    var paragraphStyle: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    static func defaultConfig() -> MarkdownStyleConfig {
        MarkdownStyleConfig(
            fontName: ".AppleSystemUIFont",
            fontSize: 16,
            textColor: NSColor.labelColor,
            backgroundColor: NSColor.textBackgroundColor,
            lineSpacing: 4,
            colorScheme: .light
        )
    }
}

private final class MarkdownHighlighter {
    private let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6}\\s+)(.+)$",
        options: [.anchorsMatchLines]
    )
    private let boldRegex = try! NSRegularExpression(pattern: "\\*\\*([^\\n]+?)\\*\\*")
    private let italicRegex = try! NSRegularExpression(
        pattern: "(?<!\\w)_([^\\n]+?)_(?!\\w)"
    )
    private let markRegex = try! NSRegularExpression(pattern: "::([^\\n]+?)::")
    private let deleteRegex = try! NSRegularExpression(pattern: "\\|\\|([^\\n]+?)\\|\\|")
    private let inlineCommentRegex = try! NSRegularExpression(pattern: "\\+\\+([^\\n]+?)\\+\\+")
    private let blockCommentRegex = try! NSRegularExpression(
        pattern: "^(%%\\s*)(.*)$",
        options: [.anchorsMatchLines]
    )
    private let annotationRegex = try! NSRegularExpression(pattern: "\\{([^\\n]+?)\\}")
    private let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\n\\]]+?)\\]")
    private let quoteRegex = try! NSRegularExpression(
        pattern: "^(>\\s+)(.*)$",
        options: [.anchorsMatchLines]
    )
    private let dividerRegex = try! NSRegularExpression(
        pattern: "^----\\s*$",
        options: [.anchorsMatchLines]
    )
    private let footnoteRegex = try! NSRegularExpression(pattern: "\\((fn)\\)")
    private let imageRegex = try! NSRegularExpression(pattern: "\\((img)\\)")
    private let inlineCodeRegex = try! NSRegularExpression(
        pattern: "(?<!\\w)'([^\\n']+?)'(?!\\w)"
    )
    private let backtickCodeRegex = try! NSRegularExpression(
        pattern: "`([^\\n`]+?)`"
    )
    private let codeBlockRegex = try! NSRegularExpression(
        pattern: "^(\\'\\'\\s*)(.*)$",
        options: [.anchorsMatchLines]
    )
    private let rawInlineRegex = try! NSRegularExpression(
        pattern: "(?<!~)~([^\\n~]+?)~(?!~)"
    )
    private let rawBlockRegex = try! NSRegularExpression(
        pattern: "^(~~\\s*)(.*)$",
        options: [.anchorsMatchLines]
    )

    func apply(to textStorage: NSTextStorage, config: MarkdownStyleConfig, activeRange: NSRange?) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: config.baseFont,
            .foregroundColor: config.textColor,
            .paragraphStyle: config.paragraphStyle
        ]
        textStorage.setAttributes(baseAttributes, range: fullRange)

        let text = textStorage.string as NSString

        applyHeadings(text, textStorage: textStorage, config: config, activeRange: activeRange)
        applyInlinePattern(
            boldRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [.font: withTraits(config.baseFont, traits: .boldFontMask)]
        )
        applyInlinePattern(
            italicRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [.font: withTraits(config.baseFont, traits: .italicFontMask)]
        )
        applyInlinePattern(
            markRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .backgroundColor: config.markBackground
            ]
        )
        applyInlinePattern(
            deleteRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .foregroundColor: config.deletionColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        applyInlinePattern(
            inlineCommentRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .foregroundColor: config.mutedTextColor,
                .backgroundColor: config.commentBackground,
                .font: withTraits(config.baseFont, traits: .italicFontMask)
            ]
        )
        applyInlinePattern(
            annotationRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .backgroundColor: config.annotationBackground
            ]
        )
        applyInlinePattern(
            linkRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .foregroundColor: config.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        applyInlinePattern(
            inlineCodeRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
                .foregroundColor: config.codeColor,
                .backgroundColor: config.codeBackground
            ]
        )
        applyInlinePattern(
            backtickCodeRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
                .foregroundColor: config.codeColor,
                .backgroundColor: config.codeBackground
            ]
        )
        applyInlinePattern(
            rawInlineRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
                .foregroundColor: config.codeColor,
                .backgroundColor: config.codeBackground
            ]
        )

        applyLinePattern(
            blockCommentRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            lineAttributes: [
                .foregroundColor: config.mutedTextColor,
                .backgroundColor: config.commentBackground,
                .font: withTraits(config.baseFont, traits: .italicFontMask)
            ],
            tokenLength: 2
        )

        applyLinePattern(
            quoteRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            lineAttributes: [
                .foregroundColor: config.quoteColor,
                .font: withTraits(config.baseFont, traits: .italicFontMask)
            ],
            tokenLength: 1,
            indent: 18
        )

        applyLinePattern(
            codeBlockRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            lineAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
                .foregroundColor: config.codeColor,
                .backgroundColor: config.codeBackground
            ],
            tokenLength: 2
        )

        applyLinePattern(
            rawBlockRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            lineAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
                .foregroundColor: config.codeColor,
                .backgroundColor: config.codeBackground
            ],
            tokenLength: 2
        )

        applyInlinePattern(
            footnoteRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .foregroundColor: config.linkColor,
                .font: withTraits(config.baseFont, traits: .boldFontMask)
            ]
        )

        applyInlinePattern(
            imageRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange,
            contentAttributes: [
                .foregroundColor: config.linkColor,
                .font: withTraits(config.baseFont, traits: .boldFontMask)
            ]
        )

        applyTokenPattern(
            dividerRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            activeRange: activeRange
        )
    }

    private func applyHeadings(
        _ text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        activeRange: NSRange?
    ) {
        headingRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
        let prefixRange = match.range(at: 1)
        let contentRange = match.range(at: 2)
        let prefixText = text.substring(with: prefixRange)
        let hashCount = prefixText.filter { $0 == "#" }.count
        let level = min(max(hashCount, 1), 4)
            let scale: CGFloat
            switch level {
            case 1:
                scale = 1.6
            case 2:
                scale = 1.4
            case 3:
                scale = 1.25
            default:
                scale = 1.15
            }

            let headingFont = withTraits(
                NSFont(name: config.fontName, size: config.fontSize * scale)
                    ?? NSFont.systemFont(ofSize: config.fontSize * scale),
                traits: .boldFontMask
            )

            textStorage.addAttributes(
                [
                    .font: headingFont,
                    .foregroundColor: config.textColor
                ],
                range: contentRange
            )
            textStorage.addAttributes(
                [
                    .foregroundColor: tokenColor(config: config, activeRange: activeRange, tokenRange: prefixRange),
                    .font: tokenFont(config: config, activeRange: activeRange, tokenRange: prefixRange)
                ],
                range: prefixRange
            )
        }
    }

    private func applyInlinePattern(
        _ regex: NSRegularExpression,
        text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        activeRange: NSRange?,
        contentAttributes: [NSAttributedString.Key: Any]
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            guard match.numberOfRanges >= 2 else { return }
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            textStorage.addAttributes(contentAttributes, range: contentRange)

            let leadingTokenLength = contentRange.location - fullRange.location
            let trailingTokenLength = fullRange.length - leadingTokenLength - contentRange.length

            if leadingTokenLength > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(
                            config: config,
                            activeRange: activeRange,
                            tokenRange: NSRange(location: fullRange.location, length: leadingTokenLength)
                        ),
                        .font: tokenFont(
                            config: config,
                            activeRange: activeRange,
                            tokenRange: NSRange(location: fullRange.location, length: leadingTokenLength)
                        )
                    ],
                    range: NSRange(location: fullRange.location, length: leadingTokenLength)
                )
            }
            if trailingTokenLength > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(
                            config: config,
                            activeRange: activeRange,
                            tokenRange: NSRange(
                                location: fullRange.location + fullRange.length - trailingTokenLength,
                                length: trailingTokenLength
                            )
                        ),
                        .font: tokenFont(
                            config: config,
                            activeRange: activeRange,
                            tokenRange: NSRange(
                                location: fullRange.location + fullRange.length - trailingTokenLength,
                                length: trailingTokenLength
                            )
                        )
                    ],
                    range: NSRange(
                        location: fullRange.location + fullRange.length - trailingTokenLength,
                        length: trailingTokenLength
                    )
                )
            }
        }
    }

    private func applyLinePattern(
        _ regex: NSRegularExpression,
        text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        activeRange: NSRange?,
        lineAttributes: [NSAttributedString.Key: Any],
        tokenLength: Int,
        indent: CGFloat = 0
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            let fullRange = match.range(at: 0)
            let prefixRange = match.numberOfRanges > 1 ? match.range(at: 1) : NSRange(location: fullRange.location, length: tokenLength)
            let isActiveLine = activeRange.map { NSIntersectionRange(fullRange, $0).length > 0 } ?? false
            textStorage.addAttributes(lineAttributes, range: fullRange)
            if tokenLength > 0, fullRange.length >= tokenLength {
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(config: config, activeRange: activeRange, tokenRange: prefixRange),
                        .font: tokenFont(config: config, activeRange: activeRange, tokenRange: prefixRange)
                    ],
                    range: prefixRange
                )
            }
            if indent > 0, isActiveLine {
                let paragraph = NSMutableParagraphStyle()
                paragraph.headIndent = indent
                paragraph.firstLineHeadIndent = indent
                paragraph.lineSpacing = config.lineSpacing
                textStorage.addAttributes([.paragraphStyle: paragraph], range: fullRange)
            }
        }
    }

    private func applyTokenPattern(
        _ regex: NSRegularExpression,
        text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        activeRange: NSRange?
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            textStorage.addAttributes(
                [
                    .foregroundColor: tokenColor(config: config, activeRange: activeRange, tokenRange: match.range),
                    .font: tokenFont(config: config, activeRange: activeRange, tokenRange: match.range)
                ],
                range: match.range
            )
        }
    }

    private func tokenColor(config: MarkdownStyleConfig, activeRange: NSRange?, tokenRange: NSRange) -> NSColor {
        guard let activeRange else { return config.tokenColor }
        let intersection = NSIntersectionRange(activeRange, tokenRange)
        return intersection.length > 0 ? config.tokenColor : config.hiddenTokenColor
    }

    private func tokenFont(config: MarkdownStyleConfig, activeRange: NSRange?, tokenRange: NSRange) -> NSFont {
        guard let activeRange else { return config.baseFont }
        let intersection = NSIntersectionRange(activeRange, tokenRange)
        return intersection.length > 0 ? config.baseFont : config.hiddenTokenFont
    }

    private func withTraits(_ font: NSFont, traits: NSFontTraitMask) -> NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: traits)
        let convertedTraits = NSFontManager.shared.traits(of: converted)
        if convertedTraits.contains(traits) {
            return converted
        }

        switch traits {
        case .boldFontMask:
            return NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
        case .italicFontMask:
            let fallback = NSFont.systemFont(ofSize: font.pointSize)
            return NSFontManager.shared.convert(fallback, toHaveTrait: .italicFontMask)
        default:
            return converted
        }
    }
}

extension MarkdownTextEditor {
    final class Coordinator: MarkdownTextEditorCoordinator {
        private var parent: MarkdownTextEditor

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
            super.init()
            updateConfig(
                fontName: parent.fontName,
                fontSize: parent.fontSize,
                textColor: parent.textColor,
                backgroundColor: parent.backgroundColor,
                lineSpacing: parent.lineSpacing,
                colorScheme: parent.colorScheme
            )
        }

        func updateParent(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        override func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            parent.text = textView.string
            super.textDidChange(notification)
        }
    }
}
