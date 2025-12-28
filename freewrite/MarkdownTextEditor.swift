import AppKit
import SwiftUI

final class TypewriterTextView: NSTextView {
    var usesManualScrolling = false

    override func scrollRangeToVisible(_ range: NSRange) {
        if usesManualScrolling {
            return
        }
        super.scrollRangeToVisible(range)
    }

}

final class AutoHideScrollView: NSScrollView {
    private var hideWorkItem: DispatchWorkItem?
    private let hideDelay: TimeInterval = 1.2
    private var isDraggingScroller = false
    
    override func scrollWheel(with event: NSEvent) {
        showScroller()
        super.scrollWheel(with: event)
        scheduleHide()
    }
    
    override func mouseDown(with event: NSEvent) {
        if isEventOnScroller(event) || isEventInScrollerGutter(event) {
            isDraggingScroller = true
            hideWorkItem?.cancel()
            showScroller()
        }
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDraggingScroller {
            showScroller()
            hideWorkItem?.cancel()
        }
        super.mouseDragged(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isDraggingScroller = false
        scheduleHide()
    }

    private func showScroller() {
        guard let scroller = verticalScroller else { return }
        scroller.isHidden = false
        scroller.animator().alphaValue = 1.0
    }
    
    private func hideScroller() {
        guard let scroller = verticalScroller else { return }
        scroller.animator().alphaValue = 0.0
    }
    
    private func scheduleHide() {
        guard !isDraggingScroller else { return }
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideScroller()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }
    
    func prepareInitialHide() {
        hideScroller()
    }
    
    private func isEventOnScroller(_ event: NSEvent) -> Bool {
        guard let scroller = verticalScroller else { return false }
        let localPoint = scroller.convert(event.locationInWindow, from: nil)
        return scroller.bounds.contains(localPoint)
    }
    
    private func isEventInScrollerGutter(_ event: NSEvent) -> Bool {
        let pointInScrollView = convert(event.locationInWindow, from: nil)
        return pointInScrollView.x >= bounds.width - 32
    }
}

enum TypewriterMode: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case typewriter = "Typewriter"

    var id: String { rawValue }
}

enum TypewriterHighlightScope: String, CaseIterable, Identifiable {
    case line = "Line"
    case sentence = "Sentence"
    case paragraph = "Paragraph"

    var id: String { rawValue }
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let backgroundColor: NSColor
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme
    let textInset: CGSize
    let topInset: CGFloat
    let bottomInset: CGFloat
    let contentWidth: CGFloat
    let typewriterMode: TypewriterMode
    let highlightScope: TypewriterHighlightScope
    let fixedScrollEnabled: Bool
    let markCurrentLine: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TypewriterTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: textInset.width, height: textInset.height)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: contentWidth, height: 0)
        textView.maxSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.layoutManager?.allowsNonContiguousLayout = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator

        let scrollView = AutoHideScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 10)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        if let scroller = scrollView.verticalScroller {
            scroller.controlSize = .mini
            scroller.scrollerStyle = .overlay
            scroller.alphaValue = 0.0
        }
        scrollView.prepareInitialHide()

        context.coordinator.configure(textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.updateParent(self)
        if let typewriterTextView = textView as? TypewriterTextView {
            typewriterTextView.usesManualScrolling = typewriterMode == .typewriter && fixedScrollEnabled
        }
        context.coordinator.updateConfig(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme,
            typewriterMode: typewriterMode,
            highlightScope: highlightScope,
            markCurrentLine: markCurrentLine,
            fixedScrollEnabled: fixedScrollEnabled
        )

        textView.backgroundColor = backgroundColor
        nsView.backgroundColor = backgroundColor
        nsView.automaticallyAdjustsContentInsets = false
        nsView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        let baseFont = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let baseLineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
        let activeLineHeight = baseLineHeight + lineSpacing
        let typewriterExtraInset: CGFloat
        if typewriterMode == .typewriter && fixedScrollEnabled {
            typewriterExtraInset = max(0, (nsView.contentView.bounds.height - activeLineHeight) / 2)
        } else {
            typewriterExtraInset = 0
        }
        let horizontalPadding = max(0, (nsView.contentView.bounds.width - contentWidth) / 2)
        textView.textContainerInset = NSSize(
            width: textInset.width + horizontalPadding,
            height: textInset.height + typewriterExtraInset
        )
        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        if textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }

        context.coordinator.applyHighlighting(to: textView)
        context.coordinator.refreshFixedScrolling()
    }
}

class MarkdownTextEditorCoordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    private let highlighter = MarkdownHighlighter()
    private var config = MarkdownStyleConfig.defaultConfig()
    private var fixedScrollEnabled = false
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    var isUpdating = false

    func updateConfig(
        fontName: String,
        fontSize: CGFloat,
        textColor: NSColor,
        backgroundColor: NSColor,
        lineSpacing: CGFloat,
        colorScheme: ColorScheme,
        typewriterMode: TypewriterMode,
        highlightScope: TypewriterHighlightScope,
        markCurrentLine: Bool,
        fixedScrollEnabled: Bool
    ) {
        config = MarkdownStyleConfig(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme,
            typewriterEnabled: typewriterMode == .typewriter,
            highlightScope: highlightScope,
            markCurrentLine: markCurrentLine
        )
        self.fixedScrollEnabled = fixedScrollEnabled
    }

    func configure(textView: NSTextView) {
        textView.string = ""
        textView.insertionPointColor = config.textColor
        applyHighlighting(to: textView)
        self.textView = textView
        self.scrollView = textView.enclosingScrollView
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard !isUpdating else { return }
        isUpdating = true
        applyHighlighting(to: textView)
        scheduleFixedScrolling()
        isUpdating = false
    }

    func applyHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        if textStorage.length > 20000 {
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: config.baseFont,
                .foregroundColor: config.textColor,
                .paragraphStyle: config.paragraphStyle
            ]
            textStorage.setAttributes(baseAttributes, range: NSRange(location: 0, length: textStorage.length))
            textView.insertionPointColor = config.textColor
            textView.typingAttributes = baseAttributes
            return
        }
        let selectedRanges = textView.selectedRanges
        let tokenActiveRange = activeLineRange(for: textView)
        let computedHighlightRange = highlightRange(for: textView)
        let highlightRange = config.typewriterEnabled ? (computedHighlightRange ?? tokenActiveRange) : nil
        let markLineRange = config.typewriterEnabled && config.markCurrentLine ? tokenActiveRange : nil
        highlighter.apply(
            to: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            highlightRange: highlightRange,
            markLineRange: markLineRange
        )
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
        scheduleFixedScrolling()
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

    private func highlightRange(for textView: NSTextView) -> NSRange? {
        guard config.typewriterEnabled else { return nil }
        guard let selectionValue = textView.selectedRanges.first as? NSValue else { return nil }
        let selectionRange = selectionValue.rangeValue
        guard selectionRange.location != NSNotFound else { return nil }
        let text = textView.string
        if text.isEmpty {
            return nil
        }
        let nsText = text as NSString
        let boundedLocation = min(selectionRange.location, max(0, nsText.length - 1))
        let searchRange = NSRange(location: boundedLocation, length: selectionRange.length)
        switch config.highlightScope {
        case .line:
            return nsText.lineRange(for: searchRange)
        case .paragraph:
            return nsText.paragraphRange(for: searchRange)
        case .sentence:
            return sentenceRange(in: text, location: boundedLocation)
        }
    }

    private func sentenceRange(in text: String, location: Int) -> NSRange? {
        guard !text.isEmpty else { return nil }
        var result: NSRange?
        let fullRange = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: fullRange, options: [.bySentences]) { _, range, _, stop in
            let nsRange = NSRange(range, in: text)
            if nsRange.location <= location && location <= nsRange.location + nsRange.length {
                result = nsRange
                stop = true
            }
        }
        return result
    }

    func refreshFixedScrolling() {
        scheduleFixedScrolling()
    }

    private func scheduleFixedScrolling() {
        DispatchQueue.main.async { [weak self] in
            self?.applyFixedScrolling()
        }
    }

    private func applyFixedScrolling() {
        guard config.typewriterEnabled else {
            return
        }
        guard fixedScrollEnabled else {
            return
        }
        guard let textView = textView,
              let scrollView = scrollView,
              let lineRect = currentLineRect(in: textView) else {
            return
        }

        let visibleRect = scrollView.documentVisibleRect
        let anchorOffset = visibleRect.height * 0.5

        let desiredOriginY = lineRect.midY - anchorOffset
        let maxOriginY = max(0, textView.bounds.height - visibleRect.height)
        let clampedOriginY = min(max(desiredOriginY, 0), maxOriginY)

        if abs(visibleRect.minY - clampedOriginY) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: visibleRect.minX, y: clampedOriginY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func currentLineRect(in textView: NSTextView) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        let length = textView.string.count
        layoutManager.ensureLayout(for: textContainer)
        let selectionRange = textView.selectedRange()
        if selectionRange.location == length,
           layoutManager.extraLineFragmentRect.height > 0 {
            var rect = layoutManager.extraLineFragmentRect
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return rect
        }

        if length == 0 {
            return nil
        }
        let location = min(selectionRange.location, max(0, length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }
}

private struct MarkdownStyleConfig {
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let backgroundColor: NSColor
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme
    let typewriterEnabled: Bool
    let highlightScope: TypewriterHighlightScope
    let markCurrentLine: Bool

    var baseFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    var tokenColor: NSColor {
        textColor.withAlphaComponent(colorScheme == .dark ? 0.45 : 0.35)
    }

    var fadedTextColor: NSColor {
        textColor.withAlphaComponent(colorScheme == .dark ? 0.35 : 0.4)
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

    var currentLineBackground: NSColor {
        colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.04)
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
            colorScheme: .light,
            typewriterEnabled: false,
            highlightScope: .line,
            markCurrentLine: false
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

    func apply(
        to textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        tokenActiveRange: NSRange?,
        highlightRange: NSRange?,
        markLineRange: NSRange?
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if config.typewriterEnabled, let highlightRange {
            let fadedAttributes: [NSAttributedString.Key: Any] = [
                .font: config.baseFont,
                .foregroundColor: config.fadedTextColor,
                .paragraphStyle: config.paragraphStyle
            ]
            textStorage.setAttributes(fadedAttributes, range: fullRange)
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .font: config.baseFont,
                .foregroundColor: config.textColor,
                .paragraphStyle: config.paragraphStyle
            ]
            textStorage.addAttributes(highlightAttributes, range: highlightRange)
        } else {
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: config.baseFont,
                .foregroundColor: config.textColor,
                .paragraphStyle: config.paragraphStyle
            ]
            textStorage.setAttributes(baseAttributes, range: fullRange)
        }

        if let markLineRange, config.typewriterEnabled {
            textStorage.addAttributes(
                [.backgroundColor: config.currentLineBackground],
                range: markLineRange
            )
        }

        let text = textStorage.string as NSString

        applyHeadings(
            text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange
        )
        applyInlinePattern(
            boldRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            contentAttributes: [.font: withTraits(config.baseFont, traits: .boldFontMask)]
        )
        applyInlinePattern(
            italicRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            contentAttributes: [.font: withTraits(config.baseFont, traits: .italicFontMask)]
        )
        applyInlinePattern(
            markRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            contentAttributes: [
                .backgroundColor: config.markBackground
            ]
        )
        applyInlinePattern(
            deleteRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
            contentAttributes: [
                .backgroundColor: config.annotationBackground
            ]
        )
        applyInlinePattern(
            linkRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange,
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
            tokenActiveRange: tokenActiveRange
        )
    }

    private func applyHeadings(
        _ text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        tokenActiveRange: NSRange?
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
                    .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange),
                    .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange)
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
        tokenActiveRange: NSRange?,
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
                            activeRange: tokenActiveRange,
                            tokenRange: NSRange(location: fullRange.location, length: leadingTokenLength)
                        ),
                        .font: tokenFont(
                            config: config,
                            activeRange: tokenActiveRange,
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
                            activeRange: tokenActiveRange,
                            tokenRange: NSRange(
                                location: fullRange.location + fullRange.length - trailingTokenLength,
                                length: trailingTokenLength
                            )
                        ),
                        .font: tokenFont(
                            config: config,
                            activeRange: tokenActiveRange,
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
        tokenActiveRange: NSRange?,
        lineAttributes: [NSAttributedString.Key: Any],
        tokenLength: Int,
        indent: CGFloat = 0
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            let fullRange = match.range(at: 0)
            let prefixRange = match.numberOfRanges > 1 ? match.range(at: 1) : NSRange(location: fullRange.location, length: tokenLength)
            let isActiveLine = tokenActiveRange.map { NSIntersectionRange(fullRange, $0).length > 0 } ?? false
            textStorage.addAttributes(lineAttributes, range: fullRange)
            if tokenLength > 0, fullRange.length >= tokenLength {
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange),
                        .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange)
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
        tokenActiveRange: NSRange?
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            textStorage.addAttributes(
                [
                    .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: match.range),
                    .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: match.range)
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
                colorScheme: parent.colorScheme,
                typewriterMode: parent.typewriterMode,
                highlightScope: parent.highlightScope,
                markCurrentLine: parent.markCurrentLine,
                fixedScrollEnabled: parent.fixedScrollEnabled
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
