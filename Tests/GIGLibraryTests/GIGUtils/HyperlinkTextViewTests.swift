//
//  HyperlinkTextViewTests.swift
//  GIGLibrary
//
//  Regression tests for C079: HTML parsing is now cached per (font size, text)
//  and the redundant second parse was removed. These assert the parse path still
//  produces correct content after the refactor and that repeated setText calls
//  with the same input remain consistent (cache is behaviour-preserving).
//

import UIKit
import Testing
@testable import GIGLibrary

@Suite("HyperlinkTextView")
@MainActor
struct HyperlinkTextViewTests {

    @Test("Given HTML with a link, when instantiated, then the parsed text and link are present")
    func htmlInitParsesTextAndLink() {
        let html = "<p>Hello <a href=\"https://gigigo.com\">world</a></p>"
        let textView = HyperlinkTextView(htmlText: html, font: UIFont.systemFont(ofSize: 14))

        #expect(textView.attributedText.string.contains("Hello"))
        #expect(textView.attributedText.string.contains("world"))

        var foundLink = false
        let full = NSRange(location: 0, length: textView.attributedText.length)
        textView.attributedText.enumerateAttribute(.link, in: full) { value, _, _ in
            if value != nil { foundLink = true }
        }
        #expect(foundLink)
    }

    @Test("Given the same HTML set twice, when read back, then the result is consistent")
    func repeatedSetTextIsConsistent() {
        let textView = HyperlinkTextView(frame: .zero, textContainer: nil)
        textView.font = UIFont.systemFont(ofSize: 12)
        let html = "<p>Cached content</p>"

        textView.setText(htmlText: html)
        let first = textView.attributedText.string

        textView.setText(htmlText: html)
        let second = textView.attributedText.string

        #expect(first == second)
        #expect(first.contains("Cached content"))
    }

    @Test("Given different HTML inputs, when set, then each renders its own content")
    func differentTextsRenderTheirOwnContent() {
        let textView = HyperlinkTextView(frame: .zero, textContainer: nil)
        textView.font = UIFont.systemFont(ofSize: 12)

        textView.setText(htmlText: "<p>First</p>")
        #expect(textView.attributedText.string.contains("First"))

        textView.setText(htmlText: "<p>Second</p>")
        #expect(textView.attributedText.string.contains("Second"))
        #expect(!textView.attributedText.string.contains("First"))
    }
}
