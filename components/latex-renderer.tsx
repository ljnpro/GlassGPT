import React, { useMemo } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
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

const MONOSPACE_FONT = Platform.select({
  ios: 'Menlo',
  android: 'monospace',
  default: 'monospace',
});

/**
 * Wrap the raw LaTeX content in appropriate delimiters for MathJax.
 * MathJaxSvg expects TeX wrapped in $$ (display) or \\( \\) (inline).
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

export function LaTeXRenderer({ content, inline = false }: LaTeXRendererProps) {
  const colors = useColors() as ThemeColors;

  const wrappedContent = useMemo(() => wrapLatex(content, inline), [content, inline]);

  if (!content.trim()) {
    return null;
  }

  return (
    <View style={inline ? styles.inlineContainer : styles.blockContainer}>
      <MathJaxSvg
        fontSize={inline ? 15 : 17}
        color={colors.foreground}
        fontCache
        style={inline ? styles.inlineMathJax : styles.blockMathJax}
      >
        {wrappedContent}
      </MathJaxSvg>
    </View>
  );
}

const styles = StyleSheet.create({
  inlineContainer: {
    alignSelf: 'flex-start',
    justifyContent: 'center',
    marginHorizontal: 1,
    marginBottom: 0,
  },
  blockContainer: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 4,
    paddingHorizontal: 4,
  },
  inlineMathJax: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    flexShrink: 1,
  },
  blockMathJax: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 1,
  },
  fallbackInlineText: {
    fontFamily: MONOSPACE_FONT,
    fontSize: 14,
    lineHeight: 18,
    fontStyle: 'italic',
  },
  fallbackBlockContainer: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 6,
  },
  fallbackBlockText: {
    fontFamily: MONOSPACE_FONT,
    fontSize: 16,
    lineHeight: 22,
    textAlign: 'center',
  },
});
