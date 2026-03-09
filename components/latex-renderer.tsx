import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Platform,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type LayoutChangeEvent,
} from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
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

interface WebViewSizeMessage {
  type: 'size';
  width: number;
  height: number;
}

const MONOSPACE_FONT = Platform.select({
  ios: 'Menlo',
  android: 'monospace',
  default: 'monospace',
});

function buildKatexHtml(content: string, color: string, inline: boolean): string {
  const serializedContent = JSON.stringify(content);
  const bodyFontSize = inline ? 16 : 18;
  const fallbackFontSize = inline ? 14 : 16;
  const displayMode = inline ? 'false' : 'true';
  const bodyDisplay = inline ? 'inline-block' : 'block';
  const bodyWidth = inline ? 'auto' : '100%';
  const bodyTextAlign = inline ? 'left' : 'center';
  const whiteSpace = inline ? 'nowrap' : 'normal';

  return `
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
    />
    <link
      rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css"
    />
    <style>
      html,
      body {
        margin: 0;
        padding: 0;
        background: transparent;
        overflow: hidden;
      }

      body {
        display: ${bodyDisplay};
        width: ${bodyWidth};
        color: ${color};
        text-align: ${bodyTextAlign};
        font-size: ${bodyFontSize}px;
        -webkit-font-smoothing: antialiased;
        text-rendering: optimizeLegibility;
      }

      #math-root {
        display: ${inline ? 'inline-block' : 'block'};
        width: ${inline ? 'auto' : '100%'};
        white-space: ${whiteSpace};
        background: transparent;
      }

      .katex-display {
        margin: 0;
      }

      .fallback {
        font-family: -apple-system, BlinkMacSystemFont, "SF Mono", Menlo, monospace;
        font-size: ${fallbackFontSize}px;
        white-space: ${inline ? 'nowrap' : 'pre-wrap'};
        word-break: break-word;
      }
    </style>
  </head>
  <body>
    <div id="math-root"></div>

    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
    <script>
      (function () {
        var latexSource = ${serializedContent};
        var root = document.getElementById('math-root');
        var displayMode = ${displayMode};

        function postMessage(payload) {
          if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
            window.ReactNativeWebView.postMessage(JSON.stringify(payload));
          }
        }

        function measure() {
          if (!root) {
            return;
          }

          var rect = root.getBoundingClientRect();
          postMessage({
            type: 'size',
            width: Math.ceil(rect.width || 0),
            height: Math.ceil(rect.height || 0),
          });
        }

        function scheduleMeasure() {
          requestAnimationFrame(measure);
          setTimeout(measure, 40);
          setTimeout(measure, 120);
          setTimeout(measure, 260);

          if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(function () {
              setTimeout(measure, 20);
              setTimeout(measure, 140);
            });
          }
        }

        function renderFallback(message) {
          if (!root) {
            return;
          }

          root.className = 'fallback';
          root.textContent = latexSource;
          postMessage({ type: 'error', message: message || 'KaTeX render failed' });
          scheduleMeasure();
        }

        function tryRender() {
          if (!window.katex || !root) {
            return false;
          }

          try {
            window.katex.render(latexSource, root, {
              displayMode: displayMode,
              throwOnError: false,
              strict: 'ignore',
              trust: false,
              output: 'html',
            });

            scheduleMeasure();
            return true;
          } catch (error) {
            renderFallback(String(error && error.message ? error.message : error));
            return true;
          }
        }

        function waitForKatex() {
          if (tryRender()) {
            return;
          }

          setTimeout(waitForKatex, 30);
        }

        window.addEventListener('load', function () {
          waitForKatex();

          setTimeout(function () {
            if (!window.katex) {
              renderFallback('KaTeX unavailable');
            }
          }, 2500);
        });

        window.addEventListener('resize', scheduleMeasure);
      })();
    </script>
  </body>
</html>`;
}

function FallbackLatex({
  content,
  color,
  inline,
}: {
  content: string;
  color: string;
  inline: boolean;
}) {
  if (inline) {
    return (
      <Text style={[styles.fallbackInlineText, { color }]}>
        {content}
      </Text>
    );
  }

  return (
    <View style={styles.fallbackBlockContainer}>
      <Text style={[styles.fallbackBlockText, { color }]}>
        {content}
      </Text>
    </View>
  );
}

export function LaTeXRenderer({ content, inline = false }: LaTeXRendererProps) {
  const colors = useColors() as ThemeColors;
  const { width: windowWidth } = useWindowDimensions();
  const [webViewHeight, setWebViewHeight] = useState(inline ? 24 : 36);
  const [webViewWidth, setWebViewWidth] = useState(inline ? 28 : 0);
  const [containerWidth, setContainerWidth] = useState(0);
  const [renderError, setRenderError] = useState(false);

  useEffect(() => {
    setWebViewHeight(inline ? 24 : 36);
    if (inline) {
      setWebViewWidth(Math.max(28, Math.min(windowWidth * 0.75, content.length * 8 + 20)));
    }
    setRenderError(false);
  }, [content, inline, windowWidth]);

  const html = useMemo(() => buildKatexHtml(content, colors.foreground, inline), [colors.foreground, content, inline]);

  const handleContainerLayout = useCallback(
    (event: LayoutChangeEvent) => {
      if (inline) {
        return;
      }

      const nextWidth = event.nativeEvent.layout.width;
      if (Math.abs(nextWidth - containerWidth) > 1) {
        setContainerWidth(nextWidth);
      }
    },
    [containerWidth, inline]
  );

  const handleMessage = useCallback(
    (event: WebViewMessageEvent) => {
      try {
        const parsed = JSON.parse(event.nativeEvent.data) as
          | WebViewSizeMessage
          | { type: 'error'; message?: string };

        if (parsed.type === 'size') {
          const nextHeight = Math.max(inline ? 22 : 30, parsed.height || 0);
          if (Math.abs(nextHeight - webViewHeight) > 1) {
            setWebViewHeight(nextHeight);
          }

          if (inline) {
            const nextWidth = Math.max(24, Math.min(parsed.width || 0, windowWidth * 0.82));
            if (Math.abs(nextWidth - webViewWidth) > 1) {
              setWebViewWidth(nextWidth);
            }
          }
        }

        if (parsed.type === 'error') {
          setRenderError(true);
        }
      } catch {
        // Ignore malformed messages.
      }
    },
    [inline, webViewHeight, webViewWidth, windowWidth]
  );

  const resolvedWidth = inline
    ? Math.max(24, Math.min(webViewWidth, windowWidth * 0.82))
    : Math.max(48, containerWidth || Math.min(windowWidth - 72, 420));

  if (!content.trim()) {
    return null;
  }

  if (renderError) {
    return <FallbackLatex content={content} color={colors.foreground} inline={inline} />;
  }

  return (
    <View
      onLayout={handleContainerLayout}
      style={[
        inline ? styles.inlineContainer : styles.blockContainer,
        !inline && { minHeight: webViewHeight },
      ]}
    >
      <WebView
        originWhitelist={['*']}
        source={{ html }}
        onMessage={handleMessage}
        onError={() => setRenderError(true)}
        onHttpError={() => setRenderError(true)}
        scrollEnabled={false}
        showsHorizontalScrollIndicator={false}
        showsVerticalScrollIndicator={false}
        bounces={false}
        overScrollMode="never"
        setSupportMultipleWindows={false}
        mixedContentMode="always"
        automaticallyAdjustContentInsets={false}
        javaScriptEnabled
        domStorageEnabled
        pointerEvents="none"
        style={[
          styles.webView,
          {
            width: resolvedWidth,
            height: webViewHeight,
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  inlineContainer: {
    alignSelf: 'flex-start',
    justifyContent: 'flex-end',
    marginHorizontal: 1,
    marginBottom: 2,
    minHeight: 22,
  },
  blockContainer: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 2,
  },
  webView: {
    backgroundColor: 'transparent',
    opacity: 0.99,
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
