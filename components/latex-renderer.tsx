import React, { useMemo } from 'react';
import { Platform, ScrollView, StyleSheet, View } from 'react-native';
import { MathJaxSvg } from 'react-native-mathjax-html-to-svg';
import { useColors } from '@/hooks/use-colors';

interface LaTeXRendererProps {
  content: string;
  inline?: boolean;
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

/**
 * Wrap the raw LaTeX content in appropriate delimiters for MathJax.
 * MathJaxSvg expects TeX wrapped in $$ (display) or \( \) (inline).
 */
function wrapLatex(content: string, inline: boolean): string {
  const trimmed = content.trim();

  // If already wrapped in delimiters, return as-is
  if (
    (trimmed.startsWith('$$') && trimmed.endsWith('$$')) ||
    (trimmed.startsWith('\\(') && trimmed.endsWith('\\)')) ||
    (trimmed.startsWith('\\[') && trimmed.endsWith('\\]'))
  ) {
    return trimmed;
  }

  // Wrap with appropriate delimiters
  if (inline) {
    return `\\(${trimmed}\\)`;
  }
  return `$$${trimmed}$$`;
}

/**
 * fontSize prop in MathJaxSvg is divided by 2 internally, then used as a
 * multiplier for the SVG ex-based dimensions. The SVG output from MathJax
 * uses "ex" units (e.g., width="8.7ex"), and the library multiplies these
 * by the internal fontSize value. Since 1ex ≈ 8-10px on mobile, we need
 * a small multiplier to keep formulas at readable size.
 *
 * fontSize=9 → internal 4.5 → E=mc² becomes ~39px wide, ~10px tall (good)
 * fontSize=10 → internal 5 → E=mc² becomes ~43px wide, ~11px tall (good)
 */
const INLINE_FONT_SIZE = 9;
const BLOCK_FONT_SIZE = 10;

export function LaTeXRenderer({ content, inline = false }: LaTeXRendererProps) {
  const colors = useColors() as ThemeColors;

  const wrappedContent = useMemo(() => wrapLatex(content, inline), [content, inline]);

  if (!content.trim()) {
    return null;
  }

  if (inline) {
    return (
      <View style={styles.inlineContainer}>
        <MathJaxSvg
          fontSize={INLINE_FONT_SIZE}
          color={colors.foreground}
          fontCache
          style={styles.inlineMathJax}
        >
          {wrappedContent}
        </MathJaxSvg>
      </View>
    );
  }

  // Block-level formulas: wrap in a horizontal ScrollView for overflow
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.blockScrollContent}
      style={styles.blockScroll}
    >
      <MathJaxSvg
        fontSize={BLOCK_FONT_SIZE}
        color={colors.foreground}
        fontCache
        style={styles.blockMathJax}
      >
        {wrappedContent}
      </MathJaxSvg>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  inlineContainer: {
    alignSelf: 'flex-start',
    justifyContent: 'center',
    marginHorizontal: 1,
    marginBottom: 0,
  },
  inlineMathJax: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    flexShrink: 1,
  },
  blockScroll: {
    width: '100%',
    marginVertical: 4,
  },
  blockScrollContent: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 4,
    minWidth: '100%',
  },
  blockMathJax: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 1,
  },
});
