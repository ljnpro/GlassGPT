# Markdown Heading Bug Root Cause

## Problem
`### Chat Defaults` is displayed as raw text instead of a styled heading.

## Root Cause
In `RichTextView`, the `AttributedString(markdown:)` is initialized with:
```swift
interpretedSyntax: .inlineOnlyPreservingWhitespace
```

This option **only parses inline Markdown** (bold, italic, code, links) but **ignores block-level syntax** like:
- Headings (`#`, `##`, `###`)
- Unordered lists (`- item`)
- Ordered lists (`1. item`)
- Horizontal rules (`---`)
- Blockquotes (`> text`)

## Solution
The `parseBlocks()` function already splits text into block parts (code blocks, LaTeX blocks, rich text).
Need to extend it to also detect heading lines and list items, then render them with appropriate styling.

Alternatively, change `.inlineOnlyPreservingWhitespace` to `.full` — but that changes how the entire text is parsed and may break whitespace handling.

Best approach: Pre-process the richText segments to detect block-level Markdown patterns (headings, lists) and render them as separate styled views.
