import React, { useMemo } from 'react';
import { View, Text, StyleSheet, Platform } from 'react-native';
import { useColors } from '@/hooks/use-colors';

interface LatexRendererProps {
  content: string;
  inline?: boolean;
}

/**
 * Renders LaTeX formulas as styled text.
 * On native iOS 26 devices, this provides a clean monospace rendering.
 * For full MathJax/KaTeX rendering, a WebView approach would be needed.
 */
export function LatexRenderer({ content, inline }: LatexRendererProps) {
  const colors = useColors();

  // Parse and format common LaTeX symbols for display
  const displayText = useMemo(() => {
    let text = content;
    // Common LaTeX symbol replacements for readable display
    const replacements: [RegExp, string][] = [
      [/\\frac\{([^}]+)\}\{([^}]+)\}/g, '($1)/($2)'],
      [/\\sqrt\{([^}]+)\}/g, '√($1)'],
      [/\\sum/g, '∑'],
      [/\\prod/g, '∏'],
      [/\\int/g, '∫'],
      [/\\infty/g, '∞'],
      [/\\alpha/g, 'α'],
      [/\\beta/g, 'β'],
      [/\\gamma/g, 'γ'],
      [/\\delta/g, 'δ'],
      [/\\epsilon/g, 'ε'],
      [/\\theta/g, 'θ'],
      [/\\lambda/g, 'λ'],
      [/\\mu/g, 'μ'],
      [/\\pi/g, 'π'],
      [/\\sigma/g, 'σ'],
      [/\\omega/g, 'ω'],
      [/\\phi/g, 'φ'],
      [/\\psi/g, 'ψ'],
      [/\\Delta/g, 'Δ'],
      [/\\Sigma/g, 'Σ'],
      [/\\Omega/g, 'Ω'],
      [/\\Phi/g, 'Φ'],
      [/\\Psi/g, 'Ψ'],
      [/\\partial/g, '∂'],
      [/\\nabla/g, '∇'],
      [/\\times/g, '×'],
      [/\\cdot/g, '·'],
      [/\\div/g, '÷'],
      [/\\pm/g, '±'],
      [/\\mp/g, '∓'],
      [/\\leq/g, '≤'],
      [/\\geq/g, '≥'],
      [/\\neq/g, '≠'],
      [/\\approx/g, '≈'],
      [/\\equiv/g, '≡'],
      [/\\rightarrow/g, '→'],
      [/\\leftarrow/g, '←'],
      [/\\Rightarrow/g, '⇒'],
      [/\\Leftarrow/g, '⇐'],
      [/\\forall/g, '∀'],
      [/\\exists/g, '∃'],
      [/\\in/g, '∈'],
      [/\\notin/g, '∉'],
      [/\\subset/g, '⊂'],
      [/\\supset/g, '⊃'],
      [/\\cup/g, '∪'],
      [/\\cap/g, '∩'],
      [/\\emptyset/g, '∅'],
      [/\\mathbb\{R\}/g, 'ℝ'],
      [/\\mathbb\{Z\}/g, 'ℤ'],
      [/\\mathbb\{N\}/g, 'ℕ'],
      [/\\mathbb\{C\}/g, 'ℂ'],
      [/\\mathbb\{Q\}/g, 'ℚ'],
      [/\\ldots/g, '…'],
      [/\\cdots/g, '⋯'],
      [/\\vdots/g, '⋮'],
      [/\\ddots/g, '⋱'],
      [/\^{([^}]+)}/g, '^($1)'],
      [/_{([^}]+)}/g, '_($1)'],
      [/\\left/g, ''],
      [/\\right/g, ''],
      [/\\text\{([^}]+)\}/g, '$1'],
      [/\\mathrm\{([^}]+)\}/g, '$1'],
      [/\\mathbf\{([^}]+)\}/g, '$1'],
      [/\\quad/g, '  '],
      [/\\qquad/g, '    '],
      [/\\\\/g, '\n'],
      [/\\,/g, ' '],
      [/\\;/g, ' '],
      [/\\!/g, ''],
    ];

    for (const [pattern, replacement] of replacements) {
      text = text.replace(pattern, replacement);
    }

    // Remove remaining backslash commands
    text = text.replace(/\\[a-zA-Z]+/g, '');
    // Clean up extra braces
    text = text.replace(/[{}]/g, '');

    return text.trim();
  }, [content]);

  if (inline) {
    return (
      <Text
        style={{
          fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
          fontSize: 14,
          color: colors.primary,
          fontStyle: 'italic',
        }}
      >
        {displayText}
      </Text>
    );
  }

  return (
    <View style={[styles.block, { backgroundColor: colors.surface, borderColor: colors.border }]}>
      <Text
        style={{
          fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
          fontSize: 15,
          color: colors.primary,
          lineHeight: 24,
          textAlign: 'center',
        }}
        selectable
      >
        {displayText}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  block: {
    borderRadius: 12,
    borderWidth: 1,
    padding: 16,
    marginVertical: 8,
    alignItems: 'center',
  },
});
