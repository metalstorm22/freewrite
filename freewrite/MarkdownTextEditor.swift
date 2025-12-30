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

final class TrackingScroller: NSScroller {
    var onBeginTracking: (() -> Void)?
    var onEndTracking: (() -> Void)?
    
    override func trackKnob(with event: NSEvent) {
        onBeginTracking?()
        super.trackKnob(with: event)
        onEndTracking?()
    }
    
    override func mouseDown(with event: NSEvent) {
        onBeginTracking?()
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onEndTracking?()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Skip drawing the track to avoid visible edges.
    }

    override func drawKnob() {
        let knobRect = self.rect(for: .knob).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3)
        (NSColor.labelColor.withAlphaComponent(0.45)).setFill()
        path.fill()
    }
}

final class OverlayScrollView: NSScrollView {
    private var hideWorkItem: DispatchWorkItem?
    private let hideDelay: TimeInterval = 1.2
    private var isDraggingScroller = false
    
    override func scrollWheel(with event: NSEvent) {
        showScroller()
        super.scrollWheel(with: event)
        scheduleHide()
    }
    
    func installTrackingCallbacks() {
        guard let trackingScroller = verticalScroller as? TrackingScroller else { return }
        trackingScroller.onBeginTracking = { [weak self] in
            self?.isDraggingScroller = true
            self?.hideWorkItem?.cancel()
            self?.showScroller()
        }
        trackingScroller.onEndTracking = { [weak self] in
            self?.isDraggingScroller = false
            self?.scheduleHide()
        }
    }
    
    func prepareInitialHide() {
        hideScroller()
    }
    
    private func showScroller() {
        guard let scroller = verticalScroller else { return }
        scroller.isHidden = false
        scroller.animator().alphaValue = 1.0
    }
    
    private func hideScroller() {
        guard let scroller = verticalScroller else { return }
        scroller.animator().alphaValue = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak scroller] in
            scroller?.isHidden = true
        }
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

        let scrollView = OverlayScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.backgroundColor = backgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 6)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -4)
        let trackingScroller = TrackingScroller()
        trackingScroller.controlSize = .mini
        trackingScroller.scrollerStyle = .overlay
        trackingScroller.knobStyle = .default
        trackingScroller.alphaValue = 0.0
        trackingScroller.wantsLayer = true
        trackingScroller.layer?.masksToBounds = true
        trackingScroller.layer?.cornerRadius = 3
        trackingScroller.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.verticalScroller = trackingScroller
        scrollView.installTrackingCallbacks()
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
        textView.layoutManager?.usesFontLeading = false
        textView.enclosingScrollView?.usesPredominantAxisScrolling = false
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
        nsView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 6)
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
        
        if let overlayScrollView = nsView as? OverlayScrollView {
            overlayScrollView.installTrackingCallbacks()
        }
        
        context.coordinator.performPendingResetIfNeeded()
        
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
    private var wasTypewriterEnabled = false
    private var pendingResetFromTypewriter = false
    private var preTypewriterVisibleOrigin: NSPoint?
    private var pendingScrollWorkItem: DispatchWorkItem?
    private var lastScrollOriginY: CGFloat?
    private let indentUnit = "      "
    private let unorderedContinuationRegex = try! NSRegularExpression(pattern: #"^(\s*[-*+]\s+)(.*)$"#)
    private let orderedContinuationRegex = try! NSRegularExpression(pattern: #"^(\s*)(\d+)([.)])\s+(.*)$"#)
    private let checklistContinuationRegex = try! NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[(?: |x|X)\]\s+)(.*)$"#)
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
        wasTypewriterEnabled = config.typewriterEnabled
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
        pendingResetFromTypewriter = wasTypewriterEnabled && !config.typewriterEnabled
        if !wasTypewriterEnabled && config.typewriterEnabled,
           let scrollView = scrollView {
            preTypewriterVisibleOrigin = scrollView.documentVisibleRect.origin
        }
    }

    func configure(textView: NSTextView) {
        textView.string = ""
        textView.insertionPointColor = config.textColor
        applyHighlighting(to: textView)
        self.textView = textView
        self.scrollView = textView.enclosingScrollView
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard replacementString == "\n" else { return true }
        guard !isUpdating else { return true }

        let nsText = textView.string as NSString
        let lineRange = nsText.lineRange(for: affectedCharRange)
        let lineString = nsText.substring(with: lineRange)
        let lineHasTrailingNewline = lineString.hasSuffix("\n")
        let lineContent = lineHasTrailingNewline ? String(lineString.dropLast()) : lineString

        if handleChecklistContinuation(in: textView, lineRange: lineRange, lineContent: lineContent, affectedRange: affectedCharRange) {
            return false
        }
        if handleOrderedContinuation(in: textView, lineRange: lineRange, lineContent: lineContent, affectedRange: affectedCharRange) {
            return false
        }
        if handleUnorderedContinuation(in: textView, lineRange: lineRange, lineContent: lineContent, affectedRange: affectedCharRange) {
            return false
        }

        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return handleIndentation(in: textView, outdent: false)
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return handleIndentation(in: textView, outdent: true)
        }
        return false
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

    private func handleChecklistContinuation(
        in textView: NSTextView,
        lineRange: NSRange,
        lineContent: String,
        affectedRange: NSRange
    ) -> Bool {
        let nsLine = lineContent as NSString
        guard let match = checklistContinuationRegex.firstMatch(in: lineContent, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return false
        }
        let prefix = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            let wasUpdating = isUpdating
            isUpdating = true
            textView.insertText("\n", replacementRange: lineRange)
            isUpdating = wasUpdating
            return true
        }
        let cleanPrefix = prefix.replacingOccurrences(
            of: #"\[(?: |x|X)\]"#,
            with: "[ ]",
            options: .regularExpression
        )
        let wasUpdating = isUpdating
        isUpdating = true
        textView.insertText("\n\(cleanPrefix)", replacementRange: affectedRange)
        isUpdating = wasUpdating
        return true
    }

    private func handleOrderedContinuation(
        in textView: NSTextView,
        lineRange: NSRange,
        lineContent: String,
        affectedRange: NSRange
    ) -> Bool {
        let lineString = (textView.string as NSString).substring(with: lineRange)
        let lineHasTrailingNewline = lineString.hasSuffix("\n")
        let nsLine = lineContent as NSString
        guard let match = orderedContinuationRegex.firstMatch(in: lineContent, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return false
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let numberString = nsLine.substring(with: match.range(at: 2))
        let separator = nsLine.substring(with: match.range(at: 3))
        let content = nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

        if content.isEmpty {
            let wasUpdating = isUpdating
            isUpdating = true
            if let parentIndent = outdentedIndent(from: indent) {
                let nsText = textView.string as NSString
                if let parentItem = previousOrderedListItem(in: nsText, before: lineRange.location, indent: parentIndent) {
                    let nextNumber = parentItem.number + 1
                    let parentLine = "\(parentIndent)\(nextNumber)\(parentItem.separator) "
                    let replacement = lineHasTrailingNewline ? parentLine + "\n" : parentLine
                    textView.insertText(replacement, replacementRange: lineRange)
                    let cursorLocation = lineRange.location + (parentLine as NSString).length
                    textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
                    if let nextLineStart = nextLineStart(in: textView.string as NSString, from: cursorLocation) {
                        renumberOrderedList(
                            in: textView,
                            startingAt: nextLineStart,
                            indent: parentIndent,
                            startingNumber: nextNumber + 1,
                            separator: parentItem.separator
                        )
                    }
                } else {
                    textView.insertText("\n", replacementRange: lineRange)
                }
            } else {
                textView.insertText("\n", replacementRange: lineRange)
            }
            isUpdating = wasUpdating
            return true
        }
        let nextNumber = (Int(numberString) ?? 0) + 1
        let continuation = "\n\(indent)\(nextNumber)\(separator) "
        let wasUpdating = isUpdating
        isUpdating = true
        textView.insertText(continuation, replacementRange: affectedRange)
        if let nextLineStart = nextLineStart(in: textView.string as NSString, from: textView.selectedRange().location) {
            renumberOrderedList(
                in: textView,
                startingAt: nextLineStart,
                indent: indent,
                startingNumber: nextNumber + 1,
                separator: separator
            )
        }
        isUpdating = wasUpdating
        return true
    }

    private func handleUnorderedContinuation(
        in textView: NSTextView,
        lineRange: NSRange,
        lineContent: String,
        affectedRange: NSRange
    ) -> Bool {
        let nsLine = lineContent as NSString
        guard let match = unorderedContinuationRegex.firstMatch(in: lineContent, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return false
        }
        let prefix = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)

        if content.isEmpty {
            let wasUpdating = isUpdating
            isUpdating = true
            textView.insertText("\n", replacementRange: lineRange)
            isUpdating = wasUpdating
            return true
        }
        let wasUpdating = isUpdating
        isUpdating = true
        textView.insertText("\n\(prefix)", replacementRange: affectedRange)
        isUpdating = wasUpdating
        return true
    }

    private func handleIndentation(in textView: NSTextView, outdent: Bool) -> Bool {
        guard let textStorage = textView.textStorage else { return false }
        if textStorage.length == 0 {
            if !outdent {
                textView.insertText(indentUnit, replacementRange: textView.selectedRange())
            }
            return true
        }
        let nsText = textStorage.string as NSString
        let selectedRange = textView.selectedRange()
        let lineRanges = lineRanges(for: selectedRange, in: nsText)
        guard !lineRanges.isEmpty else { return false }

        if selectedRange.length == 0 {
            let caretLineRange = lineRanges[0]
            let lineContent = lineContent(in: nsText, range: caretLineRange)
            if !isListLine(lineContent), !outdent {
                textView.insertText(indentUnit, replacementRange: selectedRange)
                return true
            }
        }

        var replacements: [(range: NSRange, text: String)] = []
        var orderedCounter = 0
        var previousWasOrdered = false

        for lineRange in lineRanges {
            let lineString = nsText.substring(with: lineRange)
            let hasTrailingNewline = lineString.hasSuffix("\n")
            let lineContent = hasTrailingNewline ? String(lineString.dropLast()) : lineString
            var updatedLine = lineContent

            if outdent {
                let removalLength = removableIndentLength(for: updatedLine)
                guard removalLength > 0 else { continue }
                updatedLine = String(updatedLine.dropFirst(removalLength))
            } else {
                if isOrderedListLine(updatedLine) {
                    orderedCounter = previousWasOrdered ? orderedCounter + 1 : 1
                    previousWasOrdered = true
                    updatedLine = replacingOrderedNumber(in: updatedLine, with: orderedCounter)
                } else {
                    previousWasOrdered = false
                }
                updatedLine = indentUnit + updatedLine
            }

            if hasTrailingNewline {
                updatedLine += "\n"
            }
            replacements.append((lineRange, updatedLine))
        }

        textStorage.beginEditing()
        var selectionStart = selectedRange.location
        var selectionEnd = selectedRange.location + selectedRange.length
        let selectionLength = selectedRange.length

        for replacement in replacements.reversed() {
            let oldLength = replacement.range.length
            textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
            let newLength = (replacement.text as NSString).length
            let delta = newLength - oldLength
            if delta != 0 {
                adjustSelection(
                    changeLocation: replacement.range.location,
                    delta: delta,
                    selectionStart: &selectionStart,
                    selectionEnd: &selectionEnd,
                    selectionLength: selectionLength
                )
            }
        }

        textStorage.endEditing()
        textView.didChangeText()
        let clampedStart = max(0, selectionStart)
        let clampedEnd = max(clampedStart, selectionEnd)
        textView.setSelectedRange(NSRange(location: clampedStart, length: clampedEnd - clampedStart))
        return true
    }

    private func lineRanges(for selection: NSRange, in text: NSString) -> [NSRange] {
        guard text.length > 0 else { return [] }
        var selectionEnd = selection.location + selection.length
        if selection.length > 0, selectionEnd > 0 {
            let previousCharacter = text.character(at: selectionEnd - 1)
            if previousCharacter == 10 || previousCharacter == 13 {
                selectionEnd = max(selection.location, selectionEnd - 1)
            }
        }
        let effectiveRange = NSRange(location: selection.location, length: max(0, selectionEnd - selection.location))
        let coveredRange = text.lineRange(for: effectiveRange)
        var ranges: [NSRange] = []
        var currentLocation = coveredRange.location
        let maxLocation = NSMaxRange(coveredRange)
        while currentLocation < maxLocation {
            let range = text.lineRange(for: NSRange(location: currentLocation, length: 0))
            ranges.append(range)
            currentLocation = NSMaxRange(range)
        }
        return ranges
    }

    private func lineContent(in text: NSString, range: NSRange) -> String {
        let lineString = text.substring(with: range)
        if lineString.hasSuffix("\n") {
            return String(lineString.dropLast())
        }
        return lineString
    }

    private func isListLine(_ line: String) -> Bool {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        if unorderedContinuationRegex.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        if orderedContinuationRegex.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        if checklistContinuationRegex.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        return false
    }

    private func isOrderedListLine(_ line: String) -> Bool {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        return orderedContinuationRegex.firstMatch(in: line, options: [], range: range) != nil
    }

    private func replacingOrderedNumber(in line: String, with number: Int) -> String {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = orderedContinuationRegex.firstMatch(in: line, options: [], range: range) else {
            return line
        }
        let numberRange = match.range(at: 2)
        return nsLine.replacingCharacters(in: numberRange, with: String(number))
    }

    private func removableIndentLength(for line: String) -> Int {
        guard !line.isEmpty else { return 0 }
        if line.hasPrefix("\t") {
            return 1
        }
        let leadingSpaces = line.prefix { $0 == " " }
        return min(leadingSpaces.count, indentUnit.count)
    }

    private func adjustSelection(
        changeLocation: Int,
        delta: Int,
        selectionStart: inout Int,
        selectionEnd: inout Int,
        selectionLength: Int
    ) {
        guard delta != 0 else { return }
        if changeLocation < selectionStart {
            selectionStart += delta
            selectionEnd += delta
            return
        }
        if changeLocation == selectionStart {
            if selectionLength == 0 {
                selectionStart += delta
                selectionEnd += delta
            } else {
                selectionEnd += delta
            }
            return
        }
        if changeLocation > selectionStart && changeLocation <= selectionEnd {
            selectionEnd += delta
        }
    }

    private func outdentedIndent(from indent: String) -> String? {
        guard !indent.isEmpty else { return nil }
        if indent.hasPrefix(indentUnit) {
            return String(indent.dropFirst(indentUnit.count))
        }
        if indent.hasPrefix("\t") {
            return String(indent.dropFirst())
        }
        return ""
    }

    private func nextLineStart(in text: NSString, from location: Int) -> Int? {
        guard text.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), max(text.length - 1, 0))
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))
        let nextLocation = NSMaxRange(lineRange)
        return nextLocation <= text.length ? nextLocation : nil
    }

    private func renumberOrderedList(
        in textView: NSTextView,
        startingAt location: Int,
        indent: String,
        startingNumber: Int,
        separator: String
    ) {
        guard let textStorage = textView.textStorage else { return }
        let text = textStorage.string as NSString
        guard location < text.length else { return }
        var currentLocation = location
        var number = startingNumber
        let indentLength = indent.count
        var replacements: [(range: NSRange, text: String)] = []

        while currentLocation < text.length {
            let lineRange = text.lineRange(for: NSRange(location: currentLocation, length: 0))
            let lineContent = lineContent(in: text, range: lineRange)
            let trimmed = lineContent.trimmingCharacters(in: .whitespaces)
            let leadingWhitespace = lineContent.prefix { $0 == " " || $0 == "\t" }
            let leadingCount = leadingWhitespace.count

            if trimmed.isEmpty {
                if leadingCount <= indentLength {
                    break
                }
                currentLocation = NSMaxRange(lineRange)
                continue
            }

            let nsLine = lineContent as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = orderedContinuationRegex.firstMatch(in: lineContent, options: [], range: range) {
                let lineIndent = nsLine.substring(with: match.range(at: 1))
                if lineIndent == indent {
                    let numberRange = match.range(at: 2)
                    let newNumber = String(number)
                    if nsLine.substring(with: numberRange) != newNumber {
                        let replacementRange = NSRange(
                            location: lineRange.location + numberRange.location,
                            length: numberRange.length
                        )
                        replacements.append((replacementRange, newNumber))
                    }
                    number += 1
                } else if lineIndent.count < indentLength {
                    break
                }
            } else if leadingCount < indentLength {
                break
            }

            currentLocation = NSMaxRange(lineRange)
        }

        guard !replacements.isEmpty else { return }
        textStorage.beginEditing()
        for replacement in replacements.reversed() {
            textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        textStorage.endEditing()
    }

    private func previousOrderedListItem(
        in text: NSString,
        before location: Int,
        indent: String
    ) -> (number: Int, separator: String)? {
        var searchLocation = min(max(location - 1, 0), text.length - 1)
        while searchLocation >= 0 {
            let lineRange = text.lineRange(for: NSRange(location: searchLocation, length: 0))
            let lineContent = lineContent(in: text, range: lineRange)
            let nsLine = lineContent as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = orderedContinuationRegex.firstMatch(in: lineContent, options: [], range: range) {
                let lineIndent = nsLine.substring(with: match.range(at: 1))
                if lineIndent == indent {
                    let numberString = nsLine.substring(with: match.range(at: 2))
                    let separator = nsLine.substring(with: match.range(at: 3))
                    return (Int(numberString) ?? 0, separator)
                }
            }
            if lineRange.location == 0 {
                break
            }
            searchLocation = lineRange.location - 1
        }
        return nil
    }

    func refreshFixedScrolling() {
        scheduleFixedScrolling()
    }

    private func scheduleFixedScrolling() {
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScrollWorkItem = nil
            self.applyFixedScrolling()
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
    }

    private func applyFixedScrolling() {
        guard config.typewriterEnabled else { return }
        guard fixedScrollEnabled else { return }
        guard let textView = textView,
              let scrollView = scrollView,
              let caretRect = caretRect(for: textView.selectedRange(), in: textView) else { return }

        let visibleRect = scrollView.documentVisibleRect
        let anchorOffset = visibleRect.height * 0.5
        let desiredOriginY = caretRect.midY - anchorOffset

        let halfLinePadding = max(0, caretRect.height * 0.5)
        let paddedContentHeight = textView.bounds.height + halfLinePadding
        let maxOriginY = max(0, paddedContentHeight - visibleRect.height)
        let clampedOriginY = min(max(desiredOriginY, 0), maxOriginY)
        let currentOriginX = scrollView.contentView.bounds.origin.x
        let currentOriginY = scrollView.contentView.bounds.origin.y
        let targetPoint = NSPoint(x: currentOriginX, y: clampedOriginY)

        guard abs(currentOriginY - clampedOriginY) > 0.5 || abs(visibleRect.minX - targetPoint.x) > 0.5 else {
            lastScrollOriginY = currentOriginY
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            scrollView.contentView.animator().setBoundsOrigin(targetPoint)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        lastScrollOriginY = clampedOriginY
    }

    private func resetFromTypewriterMode() {
        guard let textView = textView, let scrollView = scrollView else { return }
        let selectionRange = textView.selectedRange()
        DispatchQueue.main.async {
            guard let caretRect = self.caretRect(for: selectionRange, in: textView) else {
                textView.scrollRangeToVisible(selectionRange)
                return
            }
            
            let margin: CGFloat = 12
            var targetRect = caretRect.insetBy(dx: 0, dy: -margin)
            var visible = scrollView.documentVisibleRect
            
            let maxOriginY = max(0, textView.bounds.height - visible.height)
            var newOriginY = visible.origin.y
            
            if targetRect.minY < visible.minY {
                newOriginY = max(targetRect.minY, 0)
            } else if targetRect.maxY > visible.maxY {
                newOriginY = min(targetRect.maxY - visible.height, maxOriginY)
            }
            
            if abs(newOriginY - visible.origin.y) > 0.5 {
                visible.origin.y = newOriginY
                scrollView.contentView.scroll(to: visible.origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            
            if let savedOrigin = self.preTypewriterVisibleOrigin {
                var target = savedOrigin
                let maxOriginY = max(0, textView.bounds.height - visible.height)
                target.x = 0
                target.y = min(max(target.y, 0), maxOriginY)
                scrollView.contentView.scroll(to: target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                self.preTypewriterVisibleOrigin = nil
            }
        }
    }
    
    private func caretRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let location = max(0, min(range.location, textView.string.count > 0 ? textView.string.count - 1 : 0))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }
    
    func performPendingResetIfNeeded() {
        guard pendingResetFromTypewriter else { return }
        pendingResetFromTypewriter = false
        resetFromTypewriterMode()
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
    private let italicStarRegex = try! NSRegularExpression(
        pattern: "(?<!\\*)\\*([^\\n*]+?)\\*(?!\\*)"
    )
    private let boldItalicRegex = try! NSRegularExpression(
        pattern: "(\\*\\*\\*|___)([^\\n]+?)\\1"
    )
    private let boldDoubleUnderscoreRegex = try! NSRegularExpression(
        pattern: "__(?!_)([^\\n]+?)(?<!_)__"
    )
    private let italicRegex = try! NSRegularExpression(
        pattern: "(?<!\\w)_([^\\n]+?)_(?!\\w)"
    )
    private let markRegex = try! NSRegularExpression(pattern: "::([^\\n]+?)::")
    private let deleteRegex = try! NSRegularExpression(pattern: "\\|\\|([^\\n]+?)\\|\\|")
    private let strikethroughRegex = try! NSRegularExpression(pattern: "~~([^\\n]+?)~~")
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
    private let fencedCodeRegex = try! NSRegularExpression(
        pattern: "^```\\s*([A-Za-z0-9+\\-]*)\\s*$",
        options: [.anchorsMatchLines]
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
    private let unorderedListRegex = try! NSRegularExpression(
        pattern: "^(\\s*)([-*+]\\s+)(.*)$",
        options: [.anchorsMatchLines]
    )
    private let orderedListRegex = try! NSRegularExpression(
        pattern: "^(\\s*)(\\d+[.)]\\s+)(.*)$",
        options: [.anchorsMatchLines]
    )
    private let checklistRegex = try! NSRegularExpression(
        pattern: "^(\\s*)([-*+]\\s+\\[(?: |x|X)\\]\\s+)(.*)$",
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
        applyListPattern(
            unorderedListRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            baseIndent: 16,
            hideTokensWhenInactive: false
        )
        applyListPattern(
            orderedListRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            baseIndent: 20,
            hideTokensWhenInactive: false
        )
        applyListPattern(
            checklistRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            baseIndent: 24,
            hideTokensWhenInactive: false
        )
        applyInlinePattern(
            boldItalicRegex,
            text: text,
            textStorage: textStorage,
            config: config,
            tokenActiveRange: tokenActiveRange,
            contentAttributes: [.font: withTraits(config.baseFont, traits: [.boldFontMask, .italicFontMask])]
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
            boldDoubleUnderscoreRegex,
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
            italicStarRegex,
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
            strikethroughRegex,
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
            tokenActiveRange: tokenActiveRange,
            hideTokensWhenInactive: false
        )
        applyFencedCodeBlocks(
            text,
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
    let level = min(max(hashCount, 1), 6)
        let scale: CGFloat
        switch level {
        case 1:
            scale = 1.6
        case 2:
            scale = 1.4
        case 3:
            scale = 1.25
        case 4:
            scale = 1.15
        case 5:
            scale = 1.1
        default:
            scale = 1.05
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
        indent: CGFloat = 0,
        hideTokensWhenInactive: Bool = true
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            let fullRange = match.range(at: 0)
            let prefixRange = match.numberOfRanges > 1 ? match.range(at: 1) : NSRange(location: fullRange.location, length: tokenLength)
            textStorage.addAttributes(lineAttributes, range: fullRange)
            if tokenLength > 0, fullRange.length >= tokenLength {
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange, hideWhenInactive: hideTokensWhenInactive),
                        .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: prefixRange, hideWhenInactive: hideTokensWhenInactive)
                    ],
                    range: prefixRange
                )
            }
            if indent > 0 {
                textStorage.addAttributes(
                    [
                        .paragraphStyle: indentedParagraph(config: config, indent: indent)
                    ],
                    range: fullRange
                )
            }
        }
    }

    private func applyListPattern(
        _ regex: NSRegularExpression,
        text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        tokenActiveRange: NSRange?,
        baseIndent: CGFloat,
        hideTokensWhenInactive: Bool = false
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            guard match.numberOfRanges >= 3 else { return }
            let fullRange = match.range(at: 0)
            let leadingWhitespaceRange = match.range(at: 1)
            let tokenRange = match.range(at: 2)
            let contentRange = match.range(at: 3)
            let contentText = text.substring(with: contentRange)
            let contentIsEmpty = contentText.trimmingCharacters(in: .whitespaces).isEmpty
            let leadingWhitespaceWidth = whitespaceWidth(
                in: text,
                range: leadingWhitespaceRange,
                font: config.baseFont
            )
            textStorage.addAttributes(
                [
                    .paragraphStyle: listParagraph(
                        config: config,
                        baseIndent: baseIndent,
                        leadingWhitespaceWidth: leadingWhitespaceWidth
                    )
                ],
                range: fullRange
            )
            if tokenRange.length > 0 {
                let tokenAttributes: [NSAttributedString.Key: Any]
                if contentIsEmpty {
                    tokenAttributes = [
                        .foregroundColor: config.textColor,
                        .font: config.baseFont
                    ]
                } else {
                    tokenAttributes = [
                        .foregroundColor: tokenColor(
                            config: config,
                            activeRange: tokenActiveRange,
                            tokenRange: tokenRange,
                            hideWhenInactive: hideTokensWhenInactive
                        ),
                        .font: tokenFont(
                            config: config,
                            activeRange: tokenActiveRange,
                            tokenRange: tokenRange,
                            hideWhenInactive: hideTokensWhenInactive
                        )
                    ]
                }
                textStorage.addAttributes(tokenAttributes, range: tokenRange)
            }
        }
    }

    private func applyTokenPattern(
        _ regex: NSRegularExpression,
        text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        tokenActiveRange: NSRange?,
        hideTokensWhenInactive: Bool = true
    ) {
        regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).forEach { match in
            textStorage.addAttributes(
                [
                    .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: match.range, hideWhenInactive: hideTokensWhenInactive),
                    .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: match.range, hideWhenInactive: hideTokensWhenInactive)
                ],
                range: match.range
            )
        }
    }

    private func tokenColor(
        config: MarkdownStyleConfig,
        activeRange: NSRange?,
        tokenRange: NSRange,
        hideWhenInactive: Bool = true
    ) -> NSColor {
        if !hideWhenInactive {
            return config.tokenColor
        }
        guard let activeRange else { return config.tokenColor }
        let intersection = NSIntersectionRange(activeRange, tokenRange)
        return intersection.length > 0 ? config.tokenColor : config.hiddenTokenColor
    }

    private func tokenFont(
        config: MarkdownStyleConfig,
        activeRange: NSRange?,
        tokenRange: NSRange,
        hideWhenInactive: Bool = true
    ) -> NSFont {
        if !hideWhenInactive {
            return config.baseFont
        }
        guard let activeRange else { return config.baseFont }
        let intersection = NSIntersectionRange(activeRange, tokenRange)
        return intersection.length > 0 ? config.baseFont : config.hiddenTokenFont
    }

    private func indentedParagraph(config: MarkdownStyleConfig, indent: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = config.lineSpacing
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        return paragraph
    }

    private func listParagraph(
        config: MarkdownStyleConfig,
        baseIndent: CGFloat,
        leadingWhitespaceWidth: CGFloat
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = config.lineSpacing
        paragraph.firstLineHeadIndent = baseIndent
        paragraph.headIndent = baseIndent + leadingWhitespaceWidth
        return paragraph
    }

    private func whitespaceWidth(in text: NSString, range: NSRange, font: NSFont) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let whitespace = text.substring(with: range)
        return (whitespace as NSString).size(withAttributes: [.font: font]).width
    }

    private func applyFencedCodeBlocks(
        _ text: NSString,
        textStorage: NSTextStorage,
        config: MarkdownStyleConfig,
        tokenActiveRange: NSRange?
    ) {
        let codeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: config.fontSize * 0.95, weight: .regular),
            .foregroundColor: config.codeColor,
            .backgroundColor: config.codeBackground,
            .paragraphStyle: config.paragraphStyle
        ]

        var searchLocation = 0
        let fullLength = text.length

        while searchLocation < fullLength {
            let remainingLength = fullLength - searchLocation
            let searchRange = NSRange(location: searchLocation, length: remainingLength)
            guard let startMatch = fencedCodeRegex.firstMatch(in: text as String, options: [], range: searchRange) else {
                break
            }

            let afterStartLocation = startMatch.range.location + startMatch.range.length
            guard afterStartLocation < fullLength else { break }
            let afterStartRange = NSRange(location: afterStartLocation, length: fullLength - afterStartLocation)
            guard let endMatch = fencedCodeRegex.firstMatch(in: text as String, options: [], range: afterStartRange) else {
                break
            }

            let blockLocation = startMatch.range.location
            let blockLength = endMatch.range.location + endMatch.range.length - blockLocation
            let blockRange = NSRange(location: blockLocation, length: blockLength)

            textStorage.addAttributes(codeAttributes, range: blockRange)

            [startMatch.range, endMatch.range].forEach { fenceRange in
                textStorage.addAttributes(
                    [
                        .foregroundColor: tokenColor(config: config, activeRange: tokenActiveRange, tokenRange: fenceRange),
                        .font: tokenFont(config: config, activeRange: tokenActiveRange, tokenRange: fenceRange)
                    ],
                    range: fenceRange
                )
            }

            searchLocation = endMatch.range.location + endMatch.range.length
        }
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
