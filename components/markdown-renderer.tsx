import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  Linking,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  type ListRenderItemInfo,
  type TextStyle,
} from 'react-native';
import { Image } from 'expo-image';
import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import Animated, {
  cancelAnimation,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import { useColors } from '@/hooks/use-colors';
import { LaTeXRenderer } from './latex-renderer';

interface MarkdownRendererProps {
  content: string;
  isStreaming?: boolean;
  compact?: boolean;
}

interface ThemeColors {
  primary: string;
  background: string;
  surface: string;
  foreground: string;
  muted: string;
  border: string;
  success: string;
  warning: string;
  error: string;
}

type MarkdownBlock =
  | { type: 'heading'; level: number; text: string }
  | { type: 'paragraph'; text: string }
  | { type: 'code'; language: string; text: string }
  | { type: 'blockquote'; text: string }
  | { type: 'list'; ordered: boolean; items: string[] }
  | { type: 'table'; headers: string[]; rows: string[][] }
  | { type: 'latex'; text: string }
  | { type: 'image'; alt: string; url: string };

type InlineSegment =
  | { type: 'text'; text: string }
  | { type: 'bold'; text: string }
  | { type: 'italic'; text: string }
  | { type: 'code'; text: string }
  | { type: 'link'; text: string; url: string }
  | { type: 'latex'; text: string };

const MONOSPACE_FONT = Platform.select({
  ios: 'Menlo',
  android: 'monospace',
  default: 'monospace',
});

const HEADING_REGEX = /^\s*(#{1,6})\s+(.+?)\s*$/;
const CODE_FENCE_REGEX = /^\s*```([\w.+-]*)\s*$/;
const UNORDERED_LIST_REGEX = /^\s*[-*+]\s+(.+)\s*$/;
const ORDERED_LIST_REGEX = /^\s*(\d+)\.\s+(.+)\s*$/;
const BLOCKQUOTE_REGEX = /^\s*>\s?(.*)$/;
const TABLE_SEPARATOR_REGEX = /^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$/;
const IMAGE_REGEX = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/;

function withOpacity(color: string, opacity: number): string {
  const normalizedOpacity = Math.max(0, Math.min(1, opacity));

  if (color.startsWith('#')) {
    let hex = color.slice(1);

    if (hex.length === 3) {
      hex = hex
        .split('')
        .map((char) => char + char)
        .join('');
    }

    if (hex.length === 6) {
      const red = parseInt(hex.slice(0, 2), 16);
      const green = parseInt(hex.slice(2, 4), 16);
      const blue = parseInt(hex.slice(4, 6), 16);
      return `rgba(${red}, ${green}, ${blue}, ${normalizedOpacity})`;
    }
  }

  if (color.startsWith('rgb(')) {
    return color.replace('rgb(', 'rgba(').replace(')', `, ${normalizedOpacity})`);
  }

  if (color.startsWith('rgba(')) {
    return color.replace(/rgba\(([^,]+),([^,]+),([^,]+),[^)]+\)/, `rgba($1,$2,$3,${normalizedOpacity})`);
  }

  return color;
}

function triggerLightImpact(): void {
  if (Platform.OS !== 'web') {
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
  }
}

function triggerSuccessFeedback(): void {
  if (Platform.OS !== 'web') {
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => undefined);
  }
}

function normalizeUrl(url: string): string {
  const trimmed = url.trim();

  if (/^[a-zA-Z][a-zA-Z\d+.-]*:/.test(trimmed)) {
    return trimmed;
  }

  return `https://${trimmed}`;
}

function getBodyFontSize(compact: boolean): number {
  return compact ? 14 : 16;
}

function getBodyLineHeight(compact: boolean): number {
  return compact ? 20 : 25;
}

function getHeadingFontSize(level: number, compact: boolean): number {
  const regularSizes = [28, 24, 21, 19, 17, 16];
  const compactSizes = [22, 19, 17, 16, 15, 14];
  const sizes = compact ? compactSizes : regularSizes;
  return sizes[Math.max(0, Math.min(level - 1, sizes.length - 1))];
}

function splitTableCells(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map((cell) => cell.trim());
}

function isTableStart(lines: string[], index: number): boolean {
  if (index + 1 >= lines.length) {
    return false;
  }

  const headerLine = lines[index];
  const separatorLine = lines[index + 1];

  return headerLine.includes('|') && TABLE_SEPARATOR_REGEX.test(separatorLine);
}

function isBlockStarter(lines: string[], index: number): boolean {
  const line = lines[index];
  const trimmed = line.trim();

  if (!trimmed) {
    return true;
  }

  return (
    CODE_FENCE_REGEX.test(line) ||
    trimmed.startsWith('$$') ||
    trimmed === '\\[' ||
    trimmed.startsWith('\\[') ||
    HEADING_REGEX.test(line) ||
    BLOCKQUOTE_REGEX.test(line) ||
    UNORDERED_LIST_REGEX.test(line) ||
    ORDERED_LIST_REGEX.test(line) ||
    isTableStart(lines, index) ||
    IMAGE_REGEX.test(trimmed)
  );
}

function parseMarkdown(content: string): MarkdownBlock[] {
  const normalized = content.replace(/\r\n/g, '\n');
  const lines = normalized.split('\n');
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
      const language = codeFenceMatch[1] || 'text';
      const codeLines: string[] = [];
      index += 1;

      while (index < lines.length && !CODE_FENCE_REGEX.test(lines[index])) {
        codeLines.push(lines[index]);
        index += 1;
      }

      if (index < lines.length) {
        index += 1;
      }

      blocks.push({
        type: 'code',
        language,
        text: codeLines.join('\n'),
      });
      continue;
    }

    if (trimmed.startsWith('$$')) {
      const latexLines: string[] = [];
      const firstLineRemainder = trimmed.slice(2);

      if (firstLineRemainder.endsWith('$$') && firstLineRemainder.length > 2) {
        blocks.push({
          type: 'latex',
          text: firstLineRemainder.slice(0, -2).trim(),
        });
        index += 1;
        continue;
      }

      if (firstLineRemainder) {
        latexLines.push(firstLineRemainder);
      }

      index += 1;

      while (index < lines.length && !lines[index].trim().endsWith('$$') && lines[index].trim() !== '$$') {
        latexLines.push(lines[index]);
        index += 1;
      }

      if (index < lines.length) {
        const closingLine = lines[index].trim();
        if (closingLine !== '$$') {
          latexLines.push(closingLine.replace(/\$\$\s*$/, ''));
        }
        index += 1;
      }

      blocks.push({
        type: 'latex',
        text: latexLines.join('\n').trim(),
      });
      continue;
    }

    // Handle \[...\] block LaTeX (standard LaTeX display math)
    if (trimmed === '\\[' || trimmed.startsWith('\\[')) {
      const latexLines: string[] = [];
      // Check if \[ and \] are on the same line: \[ ... \]
      const sameLineMatch = trimmed.match(/^\\\[([\s\S]*?)\\\]$/);
      if (sameLineMatch) {
        blocks.push({
          type: 'latex',
          text: sameLineMatch[1].trim(),
        });
        index += 1;
        continue;
      }

      // \[ is on its own line or starts the content
      const afterOpener = trimmed.slice(2).trim();
      if (afterOpener) {
        latexLines.push(afterOpener);
      }

      index += 1;

      while (index < lines.length) {
        const lineTrimmed = lines[index].trim();
        if (lineTrimmed === '\\]' || lineTrimmed.endsWith('\\]')) {
          // Check if there's content before the closing \]
          const beforeCloser = lineTrimmed.replace(/\\\]\s*$/, '').trim();
          if (beforeCloser) {
            latexLines.push(beforeCloser);
          }
          index += 1;
          break;
        }
        latexLines.push(lines[index]);
        index += 1;
      }

      blocks.push({
        type: 'latex',
        text: latexLines.join('\n').trim(),
      });
      continue;
    }

    const headingMatch = currentLine.match(HEADING_REGEX);
    if (headingMatch) {
      blocks.push({
        type: 'heading',
        level: headingMatch[1].length,
        text: headingMatch[2],
      });
      index += 1;
      continue;
    }

    if (isTableStart(lines, index)) {
      const headers = splitTableCells(lines[index]);
      index += 2;

      const rows: string[][] = [];

      while (index < lines.length) {
        const rowLine = lines[index];
        const rowTrimmed = rowLine.trim();

        if (!rowTrimmed || !rowLine.includes('|')) {
          break;
        }

        rows.push(splitTableCells(rowLine));
        index += 1;
      }

      blocks.push({
        type: 'table',
        headers,
        rows,
      });
      continue;
    }

    const imageMatch = trimmed.match(IMAGE_REGEX);
    if (imageMatch) {
      blocks.push({
        type: 'image',
        alt: imageMatch[1],
        url: imageMatch[2],
      });
      index += 1;
      continue;
    }

    if (BLOCKQUOTE_REGEX.test(currentLine)) {
      const quoteLines: string[] = [];

      while (index < lines.length && BLOCKQUOTE_REGEX.test(lines[index])) {
        const match = lines[index].match(BLOCKQUOTE_REGEX);
        quoteLines.push(match?.[1] ?? '');
        index += 1;
      }

      blocks.push({
        type: 'blockquote',
        text: quoteLines.join('\n'),
      });
      continue;
    }

    if (UNORDERED_LIST_REGEX.test(currentLine)) {
      const items: string[] = [];

      while (index < lines.length && UNORDERED_LIST_REGEX.test(lines[index])) {
        const match = lines[index].match(UNORDERED_LIST_REGEX);
        items.push(match?.[1] ?? lines[index].trim());
        index += 1;
      }

      blocks.push({
        type: 'list',
        ordered: false,
        items,
      });
      continue;
    }

    if (ORDERED_LIST_REGEX.test(currentLine)) {
      const items: string[] = [];

      while (index < lines.length && ORDERED_LIST_REGEX.test(lines[index])) {
        const match = lines[index].match(ORDERED_LIST_REGEX);
        items.push(match?.[2] ?? lines[index].trim());
        index += 1;
      }

      blocks.push({
        type: 'list',
        ordered: true,
        items,
      });
      continue;
    }

    const paragraphLines: string[] = [];

    while (index < lines.length && lines[index].trim() && !isBlockStarter(lines, index)) {
      paragraphLines.push(lines[index].trimEnd());
      index += 1;
    }

    if (paragraphLines.length > 0) {
      blocks.push({
        type: 'paragraph',
        text: paragraphLines.join('\n'),
      });
      continue;
    }

    index += 1;
  }

  return blocks;
}

function findNextInlineSpecialCharacter(text: string, start: number): number {
  for (let index = start; index < text.length; index += 1) {
    const char = text[index];
    if (char === '[' || char === '`' || char === '$' || char === '*' || char === '\\') {
      return index;
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
      segments.push({
        type: 'link',
        text: linkMatch[1],
        url: linkMatch[2],
      });
      index += linkMatch[0].length;
      continue;
    }

    const codeMatch = slice.match(/^`([^`]+)`/);
    if (codeMatch) {
      segments.push({
        type: 'code',
        text: codeMatch[1],
      });
      index += codeMatch[0].length;
      continue;
    }

    const latexMatch = slice.match(/^\$([^$\n]+)\$/);
    if (latexMatch) {
      segments.push({
        type: 'latex',
        text: latexMatch[1],
      });
      index += latexMatch[0].length;
      continue;
    }

    // Handle \(...\) inline LaTeX
    const inlineLatexBackslash = slice.match(/^\\\(([\s\S]*?)\\\)/);
    if (inlineLatexBackslash) {
      segments.push({
        type: 'latex',
        text: inlineLatexBackslash[1].trim(),
      });
      index += inlineLatexBackslash[0].length;
      continue;
    }

    const boldMatch = slice.match(/^\*\*([\s\S]+?)\*\*/);
    if (boldMatch) {
      segments.push({
        type: 'bold',
        text: boldMatch[1],
      });
      index += boldMatch[0].length;
      continue;
    }

    const italicMatch = slice.match(/^\*([^*\n]+)\*/);
    if (italicMatch) {
      segments.push({
        type: 'italic',
        text: italicMatch[1],
      });
      index += italicMatch[0].length;
      continue;
    }

    const nextSpecial = findNextInlineSpecialCharacter(text, index);

    if (nextSpecial === -1) {
      segments.push({
        type: 'text',
        text: text.slice(index),
      });
      break;
    }

    if (nextSpecial === index) {
      segments.push({
        type: 'text',
        text: text[index],
      });
      index += 1;
      continue;
    }

    segments.push({
      type: 'text',
      text: text.slice(index, nextSpecial),
    });
    index = nextSpecial;
  }

  const mergedSegments: InlineSegment[] = [];

  for (const segment of segments) {
    const last = mergedSegments[mergedSegments.length - 1];

    if (segment.type === 'text' && last?.type === 'text') {
      last.text += segment.text;
    } else {
      mergedSegments.push(segment);
    }
  }

  return mergedSegments;
}

function StreamingCursor({ color, compact = false }: { color: string; compact?: boolean }) {
  const opacity = useSharedValue(1);

  useEffect(() => {
    opacity.value = withRepeat(withTiming(0.22, { duration: 620 }), -1, true);

    return () => {
      cancelAnimation(opacity);
    };
  }, [opacity]);

  const animatedStyle = useAnimatedStyle(() => {
    return {
      opacity: opacity.value,
    };
  });

  return (
    <Animated.View
      style={[
        styles.cursor,
        {
          backgroundColor: color,
          height: compact ? 16 : 18,
          width: compact ? 2.5 : 3,
        },
        animatedStyle,
      ]}
    />
  );
}

function InlineRenderer({
  text,
  colors,
  compact = false,
  fontSize,
  lineHeight,
  fontWeight,
  textColor,
}: {
  text: string;
  colors: ThemeColors;
  compact?: boolean;
  fontSize?: number;
  lineHeight?: number;
  fontWeight?: TextStyle['fontWeight'];
  textColor?: string;
}) {
  const segments = useMemo(() => parseInlineMarkdown(text), [text]);
  const resolvedFontSize = fontSize ?? getBodyFontSize(compact);
  const resolvedLineHeight = lineHeight ?? getBodyLineHeight(compact);
  const resolvedTextColor = textColor ?? colors.foreground;
  const codeFontSize = Math.max(12, resolvedFontSize - 2);
  const codeLineHeight = Math.max(16, resolvedLineHeight - 2);

  const handleOpenLink = useCallback(async (url: string) => {
    try {
      triggerLightImpact();
      await Linking.openURL(normalizeUrl(url));
    } catch {
      // Ignore invalid or unsupported URLs.
    }
  }, []);

  return (
    <View style={styles.inlineFlow}>
      {segments.map((segment, index) => {
        const key = `${segment.type}-${index}`;

        if (segment.type === 'text') {
          return (
            <Text
              key={key}
              style={[
                styles.inlineText,
                {
                  color: resolvedTextColor,
                  fontSize: resolvedFontSize,
                  lineHeight: resolvedLineHeight,
                  fontWeight,
                },
              ]}
            >
              {segment.text}
            </Text>
          );
        }

        if (segment.type === 'bold') {
          return (
            <Text
              key={key}
              style={[
                styles.inlineText,
                {
                  color: resolvedTextColor,
                  fontSize: resolvedFontSize,
                  lineHeight: resolvedLineHeight,
                  fontWeight: '700',
                },
              ]}
            >
              {segment.text}
            </Text>
          );
        }

        if (segment.type === 'italic') {
          return (
            <Text
              key={key}
              style={[
                styles.inlineText,
                {
                  color: resolvedTextColor,
                  fontSize: resolvedFontSize,
                  lineHeight: resolvedLineHeight,
                  fontStyle: 'italic',
                  fontWeight,
                },
              ]}
            >
              {segment.text}
            </Text>
          );
        }

        if (segment.type === 'code') {
          return (
            <Text
              key={key}
              style={[
                styles.inlineCodeText,
                {
                  backgroundColor: withOpacity(colors.foreground, 0.07),
                  color: compact ? '#FFB86C' : '#FF9F7A',
                  fontSize: codeFontSize,
                  lineHeight: codeLineHeight,
                  fontFamily: MONOSPACE_FONT,
                  borderColor: withOpacity(colors.border, 0.8),
                },
              ]}
            >
              {segment.text}
            </Text>
          );
        }

        if (segment.type === 'link') {
          return (
            <Text
              key={key}
              onPress={() => {
                void handleOpenLink(segment.url);
              }}
              style={[
                styles.inlineText,
                {
                  color: colors.primary,
                  fontSize: resolvedFontSize,
                  lineHeight: resolvedLineHeight,
                  textDecorationLine: 'underline',
                  fontWeight: '600',
                },
              ]}
            >
              {segment.text}
            </Text>
          );
        }

        return (
          <View key={key} style={styles.inlineMathWrapper}>
            <LaTeXRenderer content={segment.text} inline />
          </View>
        );
      })}
    </View>
  );
}

function CodeBlock({
  code,
  language,
  compact,
  colors,
}: {
  code: string;
  language: string;
  compact: boolean;
  colors: ThemeColors;
}) {
  const [copied, setCopied] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async () => {
    try {
      await Clipboard.setStringAsync(code);
      triggerSuccessFeedback();
      setCopied(true);

      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      timeoutRef.current = setTimeout(() => {
        setCopied(false);
      }, 1400);
    } catch {
      // Ignore clipboard errors.
    }
  }, [code]);

  return (
    <View
      style={[
        styles.codeBlock,
        {
          backgroundColor: '#0F1117',
          borderColor: withOpacity(colors.border, 0.55),
        },
      ]}
    >
      <View
        style={[
          styles.codeHeader,
          {
            borderBottomColor: 'rgba(255,255,255,0.08)',
            backgroundColor: 'rgba(255,255,255,0.03)',
          },
        ]}
      >
        <Text style={[styles.codeLanguageText, { color: 'rgba(255,255,255,0.55)' }]}>
          {(language || 'text').toUpperCase()}
        </Text>

        <Pressable
          onPress={handleCopy}
          style={({ pressed }) => [
            styles.codeCopyButton,
            {
              backgroundColor: pressed ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.08)',
            },
          ]}
        >
          <Text style={styles.codeCopyButtonText}>{copied ? 'Copied' : 'Copy'}</Text>
        </Pressable>
      </View>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.codeScrollContent}
        style={styles.codeScroll}
      >
        <Text
          selectable
          style={[
            styles.codeText,
            {
              color: '#E6EDF3',
              fontSize: compact ? 12 : 13,
              lineHeight: compact ? 18 : 20,
            },
          ]}
        >
          {code}
        </Text>
      </ScrollView>
    </View>
  );
}

function ListBlock({
  items,
  ordered,
  compact,
  colors,
}: {
  items: string[];
  ordered: boolean;
  compact: boolean;
  colors: ThemeColors;
}) {
  const fontSize = getBodyFontSize(compact);
  const lineHeight = getBodyLineHeight(compact);

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<string>) => {
      return (
        <View style={styles.listItemRow}>
          <Text
            style={[
              styles.listBullet,
              {
                color: colors.muted,
                fontSize,
                lineHeight,
              },
            ]}
          >
            {ordered ? `${index + 1}.` : '•'}
          </Text>

          <View style={styles.listItemContent}>
            <InlineRenderer text={item} colors={colors} compact={compact} />
          </View>
        </View>
      );
    },
    [colors, compact, fontSize, lineHeight, ordered]
  );

  return (
    <FlatList
      data={items}
      renderItem={renderItem}
      keyExtractor={(_, index) => `list-item-${index}`}
      scrollEnabled={false}
      removeClippedSubviews={false}
      contentContainerStyle={compact ? styles.compactListContent : styles.listContent}
    />
  );
}

function TableRow({
  cells,
  colors,
  compact,
  isHeader = false,
  isLastRow = false,
}: {
  cells: string[];
  colors: ThemeColors;
  compact: boolean;
  isHeader?: boolean;
  isLastRow?: boolean;
}) {
  const renderCell = useCallback(
    ({ item, index }: ListRenderItemInfo<string>) => {
      const isLastCell = index === cells.length - 1;

      return (
        <View
          style={[
            styles.tableCell,
            {
              borderColor: withOpacity(colors.border, 0.9),
              borderRightWidth: isLastCell ? 0 : StyleSheet.hairlineWidth,
              borderBottomWidth: isLastRow ? 0 : StyleSheet.hairlineWidth,
              backgroundColor: isHeader ? withOpacity(colors.foreground, 0.05) : 'transparent',
            },
          ]}
        >
          <InlineRenderer
            text={item}
            colors={colors}
            compact={compact}
            fontWeight={isHeader ? '700' : '400'}
            textColor={isHeader ? colors.foreground : colors.foreground}
          />
        </View>
      );
    },
    [cells.length, colors, compact, isHeader, isLastRow]
  );

  return (
    <FlatList
      data={cells}
      horizontal
      renderItem={renderCell}
      keyExtractor={(_, index) => `table-cell-${index}`}
      scrollEnabled={false}
      removeClippedSubviews={false}
      style={styles.tableRow}
      contentContainerStyle={styles.tableRowContent}
      showsHorizontalScrollIndicator={false}
    />
  );
}

function TableBlock({
  headers,
  rows,
  compact,
  colors,
}: {
  headers: string[];
  rows: string[][];
  compact: boolean;
  colors: ThemeColors;
}) {
  const renderRow = useCallback(
    ({ item, index }: ListRenderItemInfo<string[]>) => {
      return (
        <TableRow
          cells={item}
          colors={colors}
          compact={compact}
          isLastRow={index === rows.length - 1}
        />
      );
    },
    [colors, compact, rows.length]
  );

  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.tableScrollContent}>
      <View
        style={[
          styles.tableContainer,
          {
            borderColor: withOpacity(colors.border, 0.9),
            backgroundColor: withOpacity(colors.foreground, 0.015),
          },
        ]}
      >
        <TableRow cells={headers} colors={colors} compact={compact} isHeader isLastRow={rows.length === 0} />

        {rows.length > 0 ? (
          <FlatList
            data={rows}
            renderItem={renderRow}
            keyExtractor={(_, index) => `table-row-${index}`}
            scrollEnabled={false}
            removeClippedSubviews={false}
          />
        ) : null}
      </View>
    </ScrollView>
  );
}

function MarkdownImageBlock({
  url,
  alt,
  colors,
}: {
  url: string;
  alt: string;
  colors: ThemeColors;
}) {
  const handleOpen = useCallback(async () => {
    try {
      triggerLightImpact();
      await Linking.openURL(url);
    } catch {
      // Ignore image open failures.
    }
  }, [url]);

  return (
    <Pressable onPress={handleOpen} style={({ pressed }) => [styles.markdownImagePressable, pressed && styles.pressed]}>
      <Image
        source={{ uri: url }}
        accessibilityLabel={alt || 'Markdown image'}
        style={[
          styles.markdownImage,
          {
            backgroundColor: withOpacity(colors.foreground, 0.04),
            borderColor: withOpacity(colors.border, 0.75),
          },
        ]}
        contentFit="cover"
        transition={140}
      />
    </Pressable>
  );
}

export function MarkdownRenderer({ content, isStreaming = false, compact = false }: MarkdownRendererProps) {
  const colors = useColors() as ThemeColors;
  const blocks = useMemo(() => parseMarkdown(content), [content]);

  const renderBlock = useCallback(
    ({ item, index }: ListRenderItemInfo<MarkdownBlock>) => {
      const isFirst = index === 0;
      const blockSpacingStyle = [
        styles.block,
        compact ? styles.compactBlock : styles.regularBlock,
        isFirst && styles.firstBlock,
      ];

      if (item.type === 'heading') {
        const fontSize = getHeadingFontSize(item.level, compact);
        const lineHeight = Math.round(fontSize * 1.22);

        return (
          <View style={blockSpacingStyle}>
            <InlineRenderer
              text={item.text}
              colors={colors}
              compact={compact}
              fontSize={fontSize}
              lineHeight={lineHeight}
              fontWeight="700"
            />
          </View>
        );
      }

      if (item.type === 'paragraph') {
        return (
          <View style={blockSpacingStyle}>
            <InlineRenderer text={item.text} colors={colors} compact={compact} />
          </View>
        );
      }

      if (item.type === 'code') {
        return (
          <View style={blockSpacingStyle}>
            <CodeBlock code={item.text} language={item.language} compact={compact} colors={colors} />
          </View>
        );
      }

      if (item.type === 'blockquote') {
        return (
          <View
            style={[
              blockSpacingStyle,
              styles.blockquote,
              {
                borderLeftColor: colors.primary,
                backgroundColor: withOpacity(colors.primary, 0.08),
              },
            ]}
          >
            <InlineRenderer text={item.text} colors={colors} compact={compact} textColor={colors.foreground} />
          </View>
        );
      }

      if (item.type === 'list') {
        return (
          <View style={blockSpacingStyle}>
            <ListBlock items={item.items} ordered={item.ordered} compact={compact} colors={colors} />
          </View>
        );
      }

      if (item.type === 'table') {
        return (
          <View style={blockSpacingStyle}>
            <TableBlock headers={item.headers} rows={item.rows} compact={compact} colors={colors} />
          </View>
        );
      }

      if (item.type === 'latex') {
        return (
          <View style={blockSpacingStyle}>
            <LaTeXRenderer content={item.text} />
          </View>
        );
      }

      return (
        <View style={blockSpacingStyle}>
          <MarkdownImageBlock url={item.url} alt={item.alt} colors={colors} />
        </View>
      );
    },
    [colors, compact]
  );

  return (
    <View style={styles.root}>
      <FlatList
        data={blocks}
        renderItem={renderBlock}
        keyExtractor={(item, index) => `${item.type}-${index}`}
        scrollEnabled={false}
        removeClippedSubviews={false}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.blockListContent}
        ListFooterComponent={
          isStreaming ? (
            <View style={styles.streamingFooter}>
              <StreamingCursor color={colors.primary} compact={compact} />
            </View>
          ) : null
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    width: '100%',
  },
  blockListContent: {
    paddingVertical: 0,
  },
  block: {
    width: '100%',
  },
  firstBlock: {
    marginTop: 0,
  },
  regularBlock: {
    marginBottom: 10,
  },
  compactBlock: {
    marginBottom: 8,
  },
  inlineFlow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'flex-end',
    width: '100%',
  },
  inlineText: {
    includeFontPadding: false,
  },
  inlineCodeText: {
    overflow: 'hidden',
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 6,
    paddingVertical: 2,
    marginHorizontal: 1,
    marginBottom: 1,
  },
  inlineMathWrapper: {
    marginHorizontal: 1,
    marginBottom: 2,
  },
  blockquote: {
    borderLeftWidth: 3,
    borderRadius: 16,
    paddingLeft: 12,
    paddingRight: 10,
    paddingVertical: 10,
  },
  codeBlock: {
    borderRadius: 16,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
  },
  codeHeader: {
    minHeight: 42,
    paddingHorizontal: 14,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  codeLanguageText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
  },
  codeCopyButton: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  codeCopyButtonText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },
  codeScroll: {
    width: '100%',
  },
  codeScrollContent: {
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  codeText: {
    fontFamily: MONOSPACE_FONT,
  },
  listContent: {
    paddingVertical: 0,
  },
  compactListContent: {
    paddingVertical: 0,
  },
  listItemRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingBottom: 6,
  },
  listBullet: {
    width: 24,
    textAlign: 'right',
    marginRight: 8,
    fontWeight: '600',
  },
  listItemContent: {
    flex: 1,
  },
  tableScrollContent: {
    paddingBottom: 2,
  },
  tableContainer: {
    borderRadius: 14,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
  },
  tableRow: {
    width: '100%',
  },
  tableRowContent: {
    flexDirection: 'row',
  },
  tableCell: {
    minWidth: 120,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRightWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexShrink: 0,
  },
  markdownImagePressable: {
    width: '100%',
  },
  markdownImage: {
    width: '100%',
    height: 220,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
  },
  streamingFooter: {
    marginTop: 2,
    marginBottom: 2,
    alignSelf: 'flex-start',
    marginLeft: 1,
  },
  cursor: {
    borderRadius: 2,
  },
  pressed: {
    opacity: 0.92,
  },
});
