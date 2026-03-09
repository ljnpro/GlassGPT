import React, { useMemo, useCallback } from 'react';
import { Text, View, ScrollView, StyleSheet, Pressable, Platform } from 'react-native';
import { useColors } from '@/hooks/use-colors';
import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import { Image } from 'expo-image';
import { LatexRenderer } from './latex-renderer';

interface MarkdownRendererProps {
  content: string;
  isStreaming?: boolean;
}

type Block =
  | { type: 'paragraph'; content: string }
  | { type: 'heading'; content: string; level: number }
  | { type: 'code'; content: string; language: string }
  | { type: 'blockquote'; content: string }
  | { type: 'list'; items: string[]; ordered: boolean }
  | { type: 'hr' }
  | { type: 'image'; url: string; alt: string }
  | { type: 'latex_block'; content: string }
  | { type: 'table'; headers: string[]; rows: string[][] };

function parseMarkdown(text: string): Block[] {
  const blocks: Block[] = [];
  const lines = text.split('\n');
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code block
    if (line.trimStart().startsWith('```')) {
      const lang = line.trimStart().slice(3).trim();
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trimStart().startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // skip closing
      blocks.push({ type: 'code', content: codeLines.join('\n'), language: lang || 'text' });
      continue;
    }

    // LaTeX block $$...$$
    if (line.trim().startsWith('$$')) {
      const latexLines: string[] = [];
      const firstLine = line.trim().slice(2);
      if (firstLine && firstLine.endsWith('$$')) {
        blocks.push({ type: 'latex_block', content: firstLine.slice(0, -2).trim() });
        i++;
        continue;
      }
      if (firstLine) latexLines.push(firstLine);
      i++;
      while (i < lines.length && !lines[i].trim().endsWith('$$') && !lines[i].trim().startsWith('$$')) {
        latexLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) {
        const lastLine = lines[i].trim();
        if (lastLine !== '$$') latexLines.push(lastLine.replace(/\$\$$/, ''));
        i++;
      }
      blocks.push({ type: 'latex_block', content: latexLines.join('\n').trim() });
      continue;
    }

    // LaTeX block \[...\]
    if (line.trim().startsWith('\\[')) {
      const latexLines: string[] = [];
      const firstLine = line.trim().slice(2);
      if (firstLine.endsWith('\\]')) {
        blocks.push({ type: 'latex_block', content: firstLine.slice(0, -2).trim() });
        i++;
        continue;
      }
      if (firstLine) latexLines.push(firstLine);
      i++;
      while (i < lines.length && !lines[i].trim().endsWith('\\]')) {
        latexLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) {
        const lastLine = lines[i].trim();
        if (lastLine !== '\\]') latexLines.push(lastLine.replace(/\\\]$/, ''));
        i++;
      }
      blocks.push({ type: 'latex_block', content: latexLines.join('\n').trim() });
      continue;
    }

    // Heading
    const headingMatch = line.match(/^(#{1,6})\s+(.+)/);
    if (headingMatch) {
      blocks.push({ type: 'heading', content: headingMatch[2], level: headingMatch[1].length });
      i++;
      continue;
    }

    // HR
    if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(line.trim())) {
      blocks.push({ type: 'hr' });
      i++;
      continue;
    }

    // Table
    if (line.includes('|') && i + 1 < lines.length && /^\s*\|?\s*[-:]+/.test(lines[i + 1])) {
      const parseRow = (row: string) =>
        row.split('|').map((c) => c.trim()).filter((c) => c.length > 0);
      const headers = parseRow(line);
      i += 2; // skip header and separator
      const rows: string[][] = [];
      while (i < lines.length && lines[i].includes('|')) {
        rows.push(parseRow(lines[i]));
        i++;
      }
      blocks.push({ type: 'table', headers, rows });
      continue;
    }

    // Blockquote
    if (line.trimStart().startsWith('> ')) {
      const quoteLines: string[] = [];
      while (i < lines.length && lines[i].trimStart().startsWith('> ')) {
        quoteLines.push(lines[i].trimStart().slice(2));
        i++;
      }
      blocks.push({ type: 'blockquote', content: quoteLines.join('\n') });
      continue;
    }

    // Unordered list
    if (/^\s*[-*+]\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*[-*+]\s+/, ''));
        i++;
      }
      blocks.push({ type: 'list', items, ordered: false });
      continue;
    }

    // Ordered list
    if (/^\s*\d+\.\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+\.\s+/, ''));
        i++;
      }
      blocks.push({ type: 'list', items, ordered: true });
      continue;
    }

    // Image
    const imgMatch = line.match(/!\[([^\]]*)\]\(([^)]+)\)/);
    if (imgMatch) {
      blocks.push({ type: 'image', alt: imgMatch[1], url: imgMatch[2] });
      i++;
      continue;
    }

    // Empty line
    if (line.trim() === '') {
      i++;
      continue;
    }

    // Paragraph
    const paraLines: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== '' &&
      !lines[i].trimStart().startsWith('```') &&
      !lines[i].trimStart().startsWith('#') &&
      !lines[i].trimStart().startsWith('> ') &&
      !/^\s*[-*+]\s+/.test(lines[i]) &&
      !/^\s*\d+\.\s+/.test(lines[i]) &&
      !lines[i].trim().startsWith('$$') &&
      !lines[i].trim().startsWith('\\[')
    ) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      blocks.push({ type: 'paragraph', content: paraLines.join('\n') });
    }
  }

  return blocks;
}

// Inline markdown parser with LaTeX support
function InlineText({ text, colors }: { text: string; colors: any }) {
  const parts = useMemo(() => {
    const result: Array<{
      type: 'text' | 'bold' | 'italic' | 'bolditalic' | 'code' | 'link' | 'latex' | 'strikethrough';
      content: string;
      url?: string;
    }> = [];

    // Process inline elements
    const regex =
      /(\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|\$([^$\n]+)\$|\\\\?\((.+?)\\\\?\))/g;
    let lastIndex = 0;
    let match;

    while ((match = regex.exec(text)) !== null) {
      if (match.index > lastIndex) {
        result.push({ type: 'text', content: text.slice(lastIndex, match.index) });
      }
      if (match[2]) {
        result.push({ type: 'bolditalic', content: match[2] });
      } else if (match[3]) {
        result.push({ type: 'bold', content: match[3] });
      } else if (match[4]) {
        result.push({ type: 'italic', content: match[4] });
      } else if (match[5]) {
        result.push({ type: 'strikethrough', content: match[5] });
      } else if (match[6]) {
        result.push({ type: 'code', content: match[6] });
      } else if (match[7] && match[8]) {
        result.push({ type: 'link', content: match[7], url: match[8] });
      } else if (match[9]) {
        result.push({ type: 'latex', content: match[9] });
      } else if (match[10]) {
        result.push({ type: 'latex', content: match[10] });
      }
      lastIndex = match.index + match[0].length;
    }
    if (lastIndex < text.length) {
      result.push({ type: 'text', content: text.slice(lastIndex) });
    }
    return result;
  }, [text]);

  return (
    <Text style={{ color: colors.foreground, fontSize: 16, lineHeight: 24 }}>
      {parts.map((part, idx) => {
        switch (part.type) {
          case 'bolditalic':
            return (
              <Text key={idx} style={{ fontWeight: '700', fontStyle: 'italic' }}>
                {part.content}
              </Text>
            );
          case 'bold':
            return (
              <Text key={idx} style={{ fontWeight: '700' }}>
                {part.content}
              </Text>
            );
          case 'italic':
            return (
              <Text key={idx} style={{ fontStyle: 'italic' }}>
                {part.content}
              </Text>
            );
          case 'strikethrough':
            return (
              <Text key={idx} style={{ textDecorationLine: 'line-through', color: colors.muted }}>
                {part.content}
              </Text>
            );
          case 'code':
            return (
              <Text
                key={idx}
                style={{
                  fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
                  fontSize: 14,
                  backgroundColor: colors.surface,
                  color: '#E06C75',
                }}
              >
                {` ${part.content} `}
              </Text>
            );
          case 'link':
            return (
              <Text key={idx} style={{ color: colors.primary, textDecorationLine: 'underline' }}>
                {part.content}
              </Text>
            );
          case 'latex':
            return <LatexRenderer key={idx} content={part.content} inline />;
          default:
            return <Text key={idx}>{part.content}</Text>;
        }
      })}
    </Text>
  );
}

function CodeBlock({ code, language, colors }: { code: string; language: string; colors: any }) {
  const [copied, setCopied] = React.useState(false);

  const handleCopy = useCallback(async () => {
    await Clipboard.setStringAsync(code);
    if (Platform.OS !== 'web') {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [code]);

  return (
    <View style={[styles.codeBlock, { backgroundColor: '#1E1E2E', borderColor: colors.border }]}>
      <View style={[styles.codeHeader, { borderBottomColor: 'rgba(255,255,255,0.1)' }]}>
        <Text style={styles.codeLang}>{language}</Text>
        <Pressable onPress={handleCopy} style={({ pressed }) => [{ opacity: pressed ? 0.6 : 1 }]}>
          <Text style={styles.copyBtn}>{copied ? '✓ Copied' : 'Copy'}</Text>
        </Pressable>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.codeScroll}>
        <Text style={styles.codeText} selectable>
          {code}
        </Text>
      </ScrollView>
    </View>
  );
}

function TableBlock({ headers, rows, colors }: { headers: string[]; rows: string[][]; colors: any }) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 8 }}>
      <View style={[styles.table, { borderColor: colors.border }]}>
        {/* Header */}
        <View style={[styles.tableRow, { backgroundColor: colors.surface }]}>
          {headers.map((h, idx) => (
            <View key={idx} style={[styles.tableCell, { borderColor: colors.border }]}>
              <Text style={{ color: colors.foreground, fontWeight: '700', fontSize: 13 }}>{h}</Text>
            </View>
          ))}
        </View>
        {/* Rows */}
        {rows.map((row, rowIdx) => (
          <View key={rowIdx} style={styles.tableRow}>
            {row.map((cell, cellIdx) => (
              <View key={cellIdx} style={[styles.tableCell, { borderColor: colors.border }]}>
                <Text style={{ color: colors.foreground, fontSize: 13 }}>{cell}</Text>
              </View>
            ))}
          </View>
        ))}
      </View>
    </ScrollView>
  );
}

export function MarkdownRenderer({ content, isStreaming }: MarkdownRendererProps) {
  const colors = useColors();
  const blocks = useMemo(() => parseMarkdown(content), [content]);

  return (
    <View style={styles.container}>
      {blocks.map((block, idx) => {
        switch (block.type) {
          case 'heading': {
            const sizes = [28, 24, 20, 18, 16, 14];
            const size = sizes[Math.min(block.level - 1, 5)];
            return (
              <Text
                key={idx}
                style={{
                  fontSize: size,
                  fontWeight: '700',
                  color: colors.foreground,
                  marginTop: idx > 0 ? 16 : 0,
                  marginBottom: 8,
                  lineHeight: size * 1.3,
                }}
              >
                {block.content}
              </Text>
            );
          }

          case 'code':
            return <CodeBlock key={idx} code={block.content} language={block.language} colors={colors} />;

          case 'latex_block':
            return <LatexRenderer key={idx} content={block.content} />;

          case 'table':
            return <TableBlock key={idx} headers={block.headers} rows={block.rows} colors={colors} />;

          case 'blockquote':
            return (
              <View
                key={idx}
                style={[styles.blockquote, { borderLeftColor: colors.primary, backgroundColor: colors.surface + '80' }]}
              >
                <InlineText text={block.content} colors={colors} />
              </View>
            );

          case 'list':
            return (
              <View key={idx} style={styles.list}>
                {block.items.map((item, itemIdx) => (
                  <View key={itemIdx} style={styles.listItem}>
                    <Text style={{ color: colors.muted, fontSize: 16, lineHeight: 24, width: 24 }}>
                      {block.ordered ? `${itemIdx + 1}.` : '•'}
                    </Text>
                    <View style={{ flex: 1 }}>
                      <InlineText text={item} colors={colors} />
                    </View>
                  </View>
                ))}
              </View>
            );

          case 'hr':
            return <View key={idx} style={[styles.hr, { backgroundColor: colors.border }]} />;

          case 'image':
            return (
              <Image
                key={idx}
                source={{ uri: block.url }}
                style={styles.image}
                contentFit="contain"
                transition={200}
              />
            );

          case 'paragraph':
          default:
            return (
              <View key={idx} style={{ marginBottom: 8 }}>
                <InlineText text={block.content} colors={colors} />
              </View>
            );
        }
      })}
      {isStreaming && (
        <Text style={{ color: colors.primary, fontSize: 18, lineHeight: 24 }}>▊</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 4,
  },
  codeBlock: {
    borderRadius: 12,
    borderWidth: 1,
    marginVertical: 8,
    overflow: 'hidden',
  },
  codeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderBottomWidth: 1,
  },
  codeLang: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    color: 'rgba(255,255,255,0.5)',
  },
  copyBtn: {
    fontSize: 13,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.6)',
  },
  codeScroll: {
    padding: 14,
  },
  codeText: {
    fontSize: 13,
    lineHeight: 20,
    color: '#E0E0E0',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  blockquote: {
    borderLeftWidth: 3,
    paddingLeft: 12,
    paddingVertical: 8,
    marginVertical: 8,
    borderRadius: 4,
    paddingRight: 8,
  },
  list: {
    marginVertical: 4,
  },
  listItem: {
    flexDirection: 'row',
    marginBottom: 4,
  },
  hr: {
    height: 1,
    marginVertical: 16,
  },
  image: {
    width: '100%',
    height: 200,
    borderRadius: 12,
    marginVertical: 8,
  },
  table: {
    borderWidth: 1,
    borderRadius: 8,
    overflow: 'hidden',
  },
  tableRow: {
    flexDirection: 'row',
  },
  tableCell: {
    borderWidth: 0.5,
    paddingHorizontal: 10,
    paddingVertical: 6,
    minWidth: 80,
  },
});
