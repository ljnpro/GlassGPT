import React, { useMemo } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SvgFromXml } from 'react-native-svg';
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

// Import MathJax internals from the installed package
const mathjax = require('react-native-mathjax-html-to-svg/mathjax/mathjax').mathjax;
const TeX = require('react-native-mathjax-html-to-svg/mathjax/input/tex').TeX;
const SVG = require('react-native-mathjax-html-to-svg/mathjax/output/svg').SVG;
const liteAdaptor = require('react-native-mathjax-html-to-svg/mathjax/adaptors/liteAdaptor').liteAdaptor;
const RegisterHTMLHandler = require('react-native-mathjax-html-to-svg/mathjax/handlers/html').RegisterHTMLHandler;
const AllPackages = require('react-native-mathjax-html-to-svg/mathjax/input/tex/AllPackages').AllPackages;
require('react-native-mathjax-html-to-svg/mathjax/util/entities/all.js');

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);

const packageList = AllPackages.sort().join(', ').split(/\s*,\s*/);

/**
 * Target font sizes in pixels for the rendered formulas.
 * 1 ex ≈ 0.5em in most fonts, and at 16px base font, 1ex ≈ 8px.
 * We use these multipliers to convert ex-based SVG dimensions to pixels.
 */
const INLINE_PX_PER_EX = 7.5;  // ~15px body text equivalent
const BLOCK_PX_PER_EX = 8.5;   // slightly larger for display math

/**
 * Render LaTeX to SVG string using MathJax, then convert ex dimensions to px.
 */
function renderLatexToSvg(
  content: string,
  color: string,
  inline: boolean
): { svg: string; width: number; height: number } | null {
  try {
    const tex = new TeX({
      packages: packageList,
      inlineMath: [['$', '$'], ['\\(', '\\)']],
      displayMath: [['$$', '$$'], ['\\[', '\\]']],
      processEscapes: true,
    });
    const svg = new SVG({
      fontCache: 'local',
      mtextInheritFont: true,
      merrorInheritFont: true,
    });

    // Wrap content in appropriate delimiters
    let wrapped = content.trim();
    if (
      !(wrapped.startsWith('$$') && wrapped.endsWith('$$')) &&
      !(wrapped.startsWith('\\(') && wrapped.endsWith('\\)')) &&
      !(wrapped.startsWith('\\[') && wrapped.endsWith('\\]'))
    ) {
      wrapped = inline ? `\\(${wrapped}\\)` : `$$${wrapped}$$`;
    }

    const html = mathjax.document(wrapped, {
      InputJax: tex,
      OutputJax: svg,
      renderActions: { assistiveMml: [] },
    });
    html.render();

    const nodes = adaptor.childNodes(adaptor.body(html.document));
    let svgXml: string | null = null;

    for (const node of nodes) {
      if (node?.kind === 'mjx-container') {
        svgXml = adaptor.innerHTML(node);
        break;
      }
    }

    if (!svgXml) return null;

    // Extract ex-based dimensions from the SVG
    const svgTag = svgXml.match(/<svg([^>]+)>/i);
    if (!svgTag) return null;

    const widthMatch = svgTag[1].match(/width="([\d.]+)ex"/i);
    const heightMatch = svgTag[1].match(/height="([\d.]+)ex"/i);

    if (!widthMatch || !heightMatch) return null;

    const exWidth = parseFloat(widthMatch[1]);
    const exHeight = parseFloat(heightMatch[1]);
    const pxPerEx = inline ? INLINE_PX_PER_EX : BLOCK_PX_PER_EX;

    const pxWidth = Math.round(exWidth * pxPerEx * 10) / 10;
    const pxHeight = Math.round(exHeight * pxPerEx * 10) / 10;

    // Replace ex dimensions with px dimensions in the SVG
    let processedSvg = svgXml.replace(
      /width="[\d.]+ex"/i,
      `width="${pxWidth}"`
    );
    processedSvg = processedSvg.replace(
      /height="[\d.]+ex"/i,
      `height="${pxHeight}"`
    );

    // Remove font-family attributes that may cause issues
    processedSvg = processedSvg.replace(/font-family="[^"]*"/gmi, '');

    // Replace currentColor with the actual color
    processedSvg = processedSvg.replace(/currentColor/gim, color);

    return { svg: processedSvg, width: pxWidth, height: pxHeight };
  } catch {
    return null;
  }
}

export function LaTeXRenderer({ content, inline = false }: LaTeXRendererProps) {
  const colors = useColors() as ThemeColors;

  const result = useMemo(
    () => renderLatexToSvg(content, colors.foreground, inline),
    [content, colors.foreground, inline]
  );

  if (!content.trim() || !result) {
    // Fallback: show raw LaTeX in monospace
    return (
      <Text style={[styles.fallbackText, { color: colors.muted }]}>
        {content}
      </Text>
    );
  }

  if (inline) {
    return (
      <View style={styles.inlineContainer}>
        <SvgFromXml
          xml={result.svg}
          width={result.width}
          height={result.height}
        />
      </View>
    );
  }

  // Block-level: center with horizontal scroll for overflow
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.blockScrollContent}
      style={styles.blockScroll}
    >
      <SvgFromXml
        xml={result.svg}
        width={result.width}
        height={result.height}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  inlineContainer: {
    alignSelf: 'flex-start',
    justifyContent: 'center',
    marginHorizontal: 2,
    marginBottom: -2,
  },
  blockScroll: {
    width: '100%',
    marginVertical: 6,
  },
  blockScrollContent: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 4,
    minWidth: '100%',
  },
  fallbackText: {
    fontFamily: 'Menlo',
    fontSize: 13,
    fontStyle: 'italic',
  },
});
