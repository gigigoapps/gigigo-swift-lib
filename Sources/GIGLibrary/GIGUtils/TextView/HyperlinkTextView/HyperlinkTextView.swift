//
//  HyperlinkTextView.swift
//  GIGLibrary
//
//  Created by Jerilyn Goncalves on 11/04/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import UIKit

public protocol HyperlinkTextViewDelegate: AnyObject {
    func didTapOnHyperlink(URL: URL)
}

public final class HyperlinkTextView: UITextView {
    
    // MARK: - Public properties
    weak public var hyperlinkDelegate: HyperlinkTextViewDelegate?
    
    // MARK: - Private properties
    private var linkTapGestureRecognizer: UITapGestureRecognizer?
    /// Caches parsed attributed strings keyed by (font size, html text).
    ///
    /// HTML parsing via `NSAttributedString(fromHTML:)` spins up WebKit and is
    /// expensive; `ExpandableTextView` re-parses on every collapse/expand. Caching
    /// keeps repeated parses of the same content off the main thread's hot path (C079).
    private var attributedTextCache: [String: NSAttributedString] = [:]
    
    // MARK: - Initalizers 
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }
    
    override public func awakeFromNib() {
        super.awakeFromNib()
        // awakeFromNib is nonisolated but UIKit always invokes it on the main thread,
        // so we can safely assume main-actor isolation to run the @MainActor setup().
        MainActor.assumeIsolated {
            self.setup()
        }
    }
    
    // MARK: - Custom initializer
    
    public init(htmlText: String, font: UIFont?) {
        super.init(frame: .zero, textContainer: nil)
        self.font = font
        let styledAttributedText = self.setupAttributedString(from: htmlText)
        self.attributedText = styledAttributedText
        self.setup()
    }
    
    // MARK: - Public methods
    
    public func setText(htmlText: String) {
        let styledAttributedText = self.setupAttributedString(from: htmlText)
        self.attributedText = styledAttributedText
    }
    
    // MARK: - Private helpers
    
    private func setup() {
        self.isEditable = false
        self.isSelectable = false
        self.isScrollEnabled = false
        self.textContainerInset = .zero
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleLinkTapGestureRecognizer(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.delaysTouchesBegan = false
        tapGestureRecognizer.delaysTouchesEnded = false
        self.addGestureRecognizer(tapGestureRecognizer)
        self.linkTapGestureRecognizer = tapGestureRecognizer
    }
    
    private func setupAttributedString(from text: String) -> NSMutableAttributedString? {
        let pointSize = self.font?.pointSize ?? 10
        let cacheKey = "\(pointSize)|\(text)"
        if let cached = self.attributedTextCache[cacheKey] {
            return NSMutableAttributedString(attributedString: cached)
        }
        // Single HTML parse. The previous `setupAttributedTextWithFont()` call was a
        // second, redundant parse whose result was immediately overwritten by the
        // caller, so it produced no visible effect while doubling the cost (C079).
        guard let styledAttributedText = NSMutableAttributedString(fromHTML: text, pointSize: pointSize, color: .darkGray) else { return nil }
        let textRange = NSRange(location: 0, length: styledAttributedText.string.count)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 10
        styledAttributedText.addAttribute(NSAttributedString.Key.paragraphStyle, value: style, range: textRange)
        self.attributedTextCache[cacheKey] = NSAttributedString(attributedString: styledAttributedText)
        return styledAttributedText
    }
    
    @objc
    private func handleLinkTapGestureRecognizer(_ recognizer: UITapGestureRecognizer) {
        
        let tapLocation = recognizer.location(in: self)
        
        // We need to get two positions since attributed links only apply to ranges with a length > 0
        var textPosition: UITextPosition?
        var nextTextPosition: UITextPosition?
        
        if let position = self.closestPosition(to: tapLocation) {
            if let aux = self.position(from: position, offset: 1) {
                textPosition = position
                nextTextPosition = aux
            } else {
                // Check if we're beyond the max length and go back by one
                if let aux = self.position(from: position, offset: -1) {
                    textPosition = aux
                    nextTextPosition = self.position(from: aux, offset: 1)
                }
            }
        }
        
        guard let fromPosition = textPosition,
            let toPosition = nextTextPosition,
            let textRange = self.textRange(from: fromPosition, to: toPosition) else {
                return
        }
        
        // Get the offset range of the character we tapped on
        let startOffset = self.offset(from: self.beginningOfDocument, to: textRange.start)
        let endOffset = self.offset(from: self.beginningOfDocument, to: textRange.end)
        let offsetRange = NSRange(location: startOffset, length: endOffset - startOffset)
        
        guard offsetRange.location != NSNotFound,
            offsetRange.length > 0,
            NSMaxRange(offsetRange) < self.attributedText.length else {
            return
        }
        
        // Grab the link from the String
        let attributedSubstring = self.attributedText.attributedSubstring(from: offsetRange)
        if let hyperlinkURL = attributedSubstring.attribute(NSAttributedString.Key.link, at: 0, effectiveRange: nil) as? NSURL,
            let hyperlink = hyperlinkURL.absoluteString,
            let URL = URL(string: hyperlink) {
            self.hyperlinkDelegate?.didTapOnHyperlink(URL: URL)
        }

    }
}
