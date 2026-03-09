/**
 * Tests for LaTeX delimiter detection in the markdown parser.
 *
 * We re-implement the core parsing logic here to test it in isolation
 * without needing React Native components.
 */
import { describe, expect, it } from "vitest";

// ---- Minimal re-implementation of the parsing functions ----

type MarkdownBlock =
  | { type: "heading"; level: number; text: string }
  | { type: "paragraph"; text: string }
  | { type: "code"; language: string; text: string }
  | { type: "blockquote"; text: string }
  | { type: "list"; ordered: boolean; items: string[] }
  | { type: "table"; headers: string[]; rows: string[][] }
  | { type: "latex"; text: string }
  | { type: "image"; alt: string; url: string };

type InlineSegment =
  | { type: "text"; text: string }
  | { type: "bold"; text: string }
  | { type: "italic"; text: string }
  | { type: "code"; text: string }
  | { type: "link"; text: string; url: string }
  | { type: "latex"; text: string };

const HEADING_REGEX = /^\s*(#{1,6})\s+(.+?)\s*$/;
const CODE_FENCE_REGEX = /^\s*```([\w.+-]*)\s*$/;
const UNORDERED_LIST_REGEX = /^\s*[-*+]\s+(.+)\s*$/;
const ORDERED_LIST_REGEX = /^\s*(\d+)\.\s+(.+)\s*$/;
const BLOCKQUOTE_REGEX = /^\s*>\s?(.*)$/;
const TABLE_SEPARATOR_REGEX =
  /^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$/;
const IMAGE_REGEX = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/;

function isTableStart(lines: string[], index: number): boolean {
  if (index + 1 >= lines.length) return false;
  const headerLine = lines[index];
  const separatorLine = lines[index + 1];
  return headerLine.includes("|") && TABLE_SEPARATOR_REGEX.test(separatorLine);
}

function isBlockStarter(lines: string[], index: number): boolean {
  const line = lines[index];
  const trimmed = line.trim();
  if (!trimmed) return true;
  return (
    CODE_FENCE_REGEX.test(line) ||
    trimmed.startsWith("$$") ||
    trimmed === "\\[" ||
    trimmed.startsWith("\\[") ||
    HEADING_REGEX.test(line) ||
    BLOCKQUOTE_REGEX.test(line) ||
    UNORDERED_LIST_REGEX.test(line) ||
    ORDERED_LIST_REGEX.test(line) ||
    isTableStart(lines, index) ||
    IMAGE_REGEX.test(trimmed)
  );
}

function parseMarkdown(content: string): MarkdownBlock[] {
  const normalized = content.replace(/\r\n/g, "\n");
  const lines = normalized.split("\n");
  const blocks: MarkdownBlock[] = [];
  let index = 0;

  while (index < lines.length) {
    const currentLine = lines[index];
    const trimmed = currentLine.trim();

    if (!trimmed) {
      index += 1;
      continue;
    }

    const codeFenceMatch = currentLine.match(CODE_FENCE_REGEX);
    if (codeFenceMatch) {
      const language = codeFenceMatch[1] || "text";
      const codeLines: string[] = [];
      index += 1;
      while (index < lines.length && !CODE_FENCE_REGEX.test(lines[index])) {
        codeLines.push(lines[index]);
        index += 1;
      }
      if (index < lines.length) index += 1;
      blocks.push({ type: "code", language, text: codeLines.join("\n") });
      continue;
    }

    if (trimmed.startsWith("$$")) {
      const latexLines: string[] = [];
      const firstLineRemainder = trimmed.slice(2);
      if (firstLineRemainder.endsWith("$$") && firstLineRemainder.length > 2) {
        blocks.push({
          type: "latex",
          text: firstLineRemainder.slice(0, -2).trim(),
        });
        index += 1;
        continue;
      }
      if (firstLineRemainder) latexLines.push(firstLineRemainder);
      index += 1;
      while (
        index < lines.length &&
        !lines[index].trim().endsWith("$$") &&
        lines[index].trim() !== "$$"
      ) {
        latexLines.push(lines[index]);
        index += 1;
      }
      if (index < lines.length) {
        const closingLine = lines[index].trim();
        if (closingLine !== "$$")
          latexLines.push(closingLine.replace(/\$\$\s*$/, ""));
        index += 1;
      }
      blocks.push({ type: "latex", text: latexLines.join("\n").trim() });
      continue;
    }

    // Handle \[...\] block LaTeX
    if (trimmed === "\\[" || trimmed.startsWith("\\[")) {
      const latexLines: string[] = [];
      const sameLineMatch = trimmed.match(/^\\\[([\s\S]*?)\\\]$/);
      if (sameLineMatch) {
        blocks.push({ type: "latex", text: sameLineMatch[1].trim() });
        index += 1;
        continue;
      }
      const afterOpener = trimmed.slice(2).trim();
      if (afterOpener) latexLines.push(afterOpener);
      index += 1;
      while (index < lines.length) {
        const lineTrimmed = lines[index].trim();
        if (lineTrimmed === "\\]" || lineTrimmed.endsWith("\\]")) {
          const beforeCloser = lineTrimmed.replace(/\\\]\s*$/, "").trim();
          if (beforeCloser) latexLines.push(beforeCloser);
          index += 1;
          break;
        }
        latexLines.push(lines[index]);
        index += 1;
      }
      blocks.push({ type: "latex", text: latexLines.join("\n").trim() });
      continue;
    }

    const headingMatch = currentLine.match(HEADING_REGEX);
    if (headingMatch) {
      blocks.push({
        type: "heading",
        level: headingMatch[1].length,
        text: headingMatch[2],
      });
      index += 1;
      continue;
    }

    if (BLOCKQUOTE_REGEX.test(currentLine)) {
      const quoteLines: string[] = [];
      while (index < lines.length && BLOCKQUOTE_REGEX.test(lines[index])) {
        const match = lines[index].match(BLOCKQUOTE_REGEX);
        quoteLines.push(match?.[1] ?? "");
        index += 1;
      }
      blocks.push({ type: "blockquote", text: quoteLines.join("\n") });
      continue;
    }

    if (UNORDERED_LIST_REGEX.test(currentLine)) {
      const items: string[] = [];
      while (
        index < lines.length &&
        UNORDERED_LIST_REGEX.test(lines[index])
      ) {
        const match = lines[index].match(UNORDERED_LIST_REGEX);
        items.push(match?.[1] ?? lines[index].trim());
        index += 1;
      }
      blocks.push({ type: "list", ordered: false, items });
      continue;
    }

    if (ORDERED_LIST_REGEX.test(currentLine)) {
      const items: string[] = [];
      while (index < lines.length && ORDERED_LIST_REGEX.test(lines[index])) {
        const match = lines[index].match(ORDERED_LIST_REGEX);
        items.push(match?.[2] ?? lines[index].trim());
        index += 1;
      }
      blocks.push({ type: "list", ordered: true, items });
      continue;
    }

    const paragraphLines: string[] = [];
    while (
      index < lines.length &&
      lines[index].trim() &&
      !isBlockStarter(lines, index)
    ) {
      paragraphLines.push(lines[index].trimEnd());
      index += 1;
    }
    if (paragraphLines.length > 0) {
      blocks.push({ type: "paragraph", text: paragraphLines.join("\n") });
      continue;
    }
    index += 1;
  }

  return blocks;
}

function findNextInlineSpecialCharacter(
  text: string,
  start: number
): number {
  for (let i = start; i < text.length; i += 1) {
    const char = text[i];
    if (
      char === "[" ||
      char === "`" ||
      char === "$" ||
      char === "*" ||
      char === "\\"
    ) {
      return i;
    }
  }
  return -1;
}

function parseInlineMarkdown(text: string): InlineSegment[] {
  const segments: InlineSegment[] = [];
  let index = 0;

  while (index < text.length) {
    const slice = text.slice(index);

    const linkMatch = slice.match(/^\[([^\]]+)\]\(([^)]+)\)/);
    if (linkMatch) {
      segments.push({ type: "link", text: linkMatch[1], url: linkMatch[2] });
      index += linkMatch[0].length;
      continue;
    }

    const codeMatch = slice.match(/^`([^`]+)`/);
    if (codeMatch) {
      segments.push({ type: "code", text: codeMatch[1] });
      index += codeMatch[0].length;
      continue;
    }

    const latexMatch = slice.match(/^\$([^$\n]+)\$/);
    if (latexMatch) {
      segments.push({ type: "latex", text: latexMatch[1] });
      index += latexMatch[0].length;
      continue;
    }

    // Handle \(...\) inline LaTeX
    const inlineLatexBackslash = slice.match(/^\\\(([\s\S]*?)\\\)/);
    if (inlineLatexBackslash) {
      segments.push({
        type: "latex",
        text: inlineLatexBackslash[1].trim(),
      });
      index += inlineLatexBackslash[0].length;
      continue;
    }

    const boldMatch = slice.match(/^\*\*([\s\S]+?)\*\*/);
    if (boldMatch) {
      segments.push({ type: "bold", text: boldMatch[1] });
      index += boldMatch[0].length;
      continue;
    }

    const italicMatch = slice.match(/^\*([^*\n]+)\*/);
    if (italicMatch) {
      segments.push({ type: "italic", text: italicMatch[1] });
      index += italicMatch[0].length;
      continue;
    }

    const nextSpecial = findNextInlineSpecialCharacter(text, index);
    if (nextSpecial === -1) {
      segments.push({ type: "text", text: text.slice(index) });
      break;
    }
    if (nextSpecial === index) {
      segments.push({ type: "text", text: text[index] });
      index += 1;
      continue;
    }
    segments.push({ type: "text", text: text.slice(index, nextSpecial) });
    index = nextSpecial;
  }

  // Merge adjacent text segments
  const merged: InlineSegment[] = [];
  for (const seg of segments) {
    const last = merged[merged.length - 1];
    if (seg.type === "text" && last?.type === "text") {
      last.text += seg.text;
    } else {
      merged.push(seg);
    }
  }
  return merged;
}

// ---- Tests ----

describe("Block-level LaTeX parsing", () => {
  it("should parse $$ block LaTeX", () => {
    const input = "$$\nE = mc^2\n$$";
    const blocks = parseMarkdown(input);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe("latex");
    expect((blocks[0] as { type: "latex"; text: string }).text).toBe(
      "E = mc^2"
    );
  });

  it("should parse \\\\[...\\\\] block LaTeX on separate lines", () => {
    const input = "\\[\nL_o(x,\\omega_o)=L_e(x,\\omega_o)\n\\]";
    const blocks = parseMarkdown(input);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe("latex");
    expect((blocks[0] as { type: "latex"; text: string }).text).toBe(
      "L_o(x,\\omega_o)=L_e(x,\\omega_o)"
    );
  });

  it("should parse \\\\[...\\\\] block LaTeX on single line", () => {
    const input = "\\[E = mc^2\\]";
    const blocks = parseMarkdown(input);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe("latex");
    expect((blocks[0] as { type: "latex"; text: string }).text).toBe(
      "E = mc^2"
    );
  });

  it("should parse \\\\[...\\\\] with multi-line content", () => {
    const input =
      "\\[\nL_o(x,\\omega_o)=L_e(x,\\omega_o)+\\int_{\\Omega}\nf_r(x,\\omega_i,\\omega_o)\\,L_i(x,\\omega_i)\n(\\mathbf n\\cdot \\omega_i)\\,d\\omega_i\n\\]";
    const blocks = parseMarkdown(input);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe("latex");
    const text = (blocks[0] as { type: "latex"; text: string }).text;
    expect(text).toContain("L_o(x,\\omega_o)");
    expect(text).toContain("\\int_{\\Omega}");
    expect(text).toContain("d\\omega_i");
  });

  it("should parse text before and after \\\\[...\\\\] block", () => {
    const input =
      "经典公式是：\n\n\\[\nE = mc^2\n\\]\n\n含义：";
    const blocks = parseMarkdown(input);
    expect(blocks.length).toBeGreaterThanOrEqual(3);
    expect(blocks[0].type).toBe("paragraph");
    expect(blocks[1].type).toBe("latex");
    expect(blocks[2].type).toBe("paragraph");
  });

  it("should handle heading followed by \\\\[...\\\\] block", () => {
    const input = "# 渲染方程\n\n\\[\nL_o = L_e + \\int f_r\n\\]";
    const blocks = parseMarkdown(input);
    expect(blocks[0].type).toBe("heading");
    expect(blocks[1].type).toBe("latex");
  });
});

describe("Inline LaTeX parsing", () => {
  it("should parse $...$ inline LaTeX", () => {
    const segments = parseInlineMarkdown("The formula $E=mc^2$ is famous");
    const latexSegs = segments.filter((s) => s.type === "latex");
    expect(latexSegs).toHaveLength(1);
    expect(latexSegs[0].text).toBe("E=mc^2");
  });

  it("should parse \\\\(...\\\\) inline LaTeX", () => {
    const segments = parseInlineMarkdown(
      "The formula \\(E=mc^2\\) is famous"
    );
    const latexSegs = segments.filter((s) => s.type === "latex");
    expect(latexSegs).toHaveLength(1);
    expect(latexSegs[0].text).toBe("E=mc^2");
  });

  it("should parse multiple \\\\(...\\\\) inline LaTeX in one line", () => {
    const segments = parseInlineMarkdown(
      "\\(L_o(x,\\omega_o)\\)：点 \\(x\\) 沿方向 \\(\\omega_o\\) 发出的光"
    );
    const latexSegs = segments.filter((s) => s.type === "latex");
    expect(latexSegs).toHaveLength(3);
    expect(latexSegs[0].text).toBe("L_o(x,\\omega_o)");
    expect(latexSegs[1].text).toBe("x");
    expect(latexSegs[2].text).toBe("\\omega_o");
  });

  it("should handle mixed inline LaTeX with text and bold", () => {
    const segments = parseInlineMarkdown(
      "**Energy** is \\(E=mc^2\\) where \\(m\\) is mass"
    );
    const types = segments.map((s) => s.type);
    expect(types).toContain("bold");
    expect(types).toContain("latex");
    expect(types).toContain("text");
  });
});
