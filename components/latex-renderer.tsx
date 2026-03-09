import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Platform,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type LayoutChangeEvent,
} from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import katex from 'katex';
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

/**
 * Build a self-contained HTML string with KaTeX CSS inlined and the formula
 * pre-rendered server-side via katex.renderToString(). No CDN fetch required.
 */
function buildKatexHtml(content: string, color: string, inline: boolean): string {
  let renderedHtml: string;
  try {
    renderedHtml = katex.renderToString(content, {
      displayMode: !inline,
      throwOnError: false,
      strict: 'ignore',
      trust: false,
      output: 'html',
    });
  } catch {
    // If KaTeX fails, show the raw LaTeX source as fallback
    const escaped = content
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    renderedHtml = `<span class="fallback">${escaped}</span>`;
  }

  const bodyFontSize = inline ? 16 : 18;
  const fallbackFontSize = inline ? 14 : 16;
  const bodyDisplay = inline ? 'inline-block' : 'block';
  const bodyWidth = inline ? 'auto' : '100%';
  const bodyTextAlign = inline ? 'left' : 'center';

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<style>
/* Minimal KaTeX CSS subset for rendering — fonts loaded from CDN */
@font-face{font-family:KaTeX_Main;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Main-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Main;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Main-Bold.woff2) format("woff2");font-weight:700;font-style:normal}
@font-face{font-family:KaTeX_Main;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Main-Italic.woff2) format("woff2");font-weight:400;font-style:italic}
@font-face{font-family:KaTeX_Main;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Main-BoldItalic.woff2) format("woff2");font-weight:700;font-style:italic}
@font-face{font-family:KaTeX_Math;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Math-Italic.woff2) format("woff2");font-weight:400;font-style:italic}
@font-face{font-family:KaTeX_Math;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Math-BoldItalic.woff2) format("woff2");font-weight:700;font-style:italic}
@font-face{font-family:KaTeX_AMS;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_AMS-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Size1;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Size1-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Size2;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Size2-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Size3;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Size3-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Size4;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Size4-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Caligraphic;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Caligraphic-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Caligraphic;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Caligraphic-Bold.woff2) format("woff2");font-weight:700;font-style:normal}
@font-face{font-family:KaTeX_Fraktur;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Fraktur-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Fraktur;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Fraktur-Bold.woff2) format("woff2");font-weight:700;font-style:normal}
@font-face{font-family:KaTeX_SansSerif;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_SansSerif-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_SansSerif;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_SansSerif-Bold.woff2) format("woff2");font-weight:700;font-style:normal}
@font-face{font-family:KaTeX_SansSerif;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_SansSerif-Italic.woff2) format("woff2");font-weight:400;font-style:italic}
@font-face{font-family:KaTeX_Script;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Script-Regular.woff2) format("woff2");font-weight:400;font-style:normal}
@font-face{font-family:KaTeX_Typewriter;src:url(https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/fonts/KaTeX_Typewriter-Regular.woff2) format("woff2");font-weight:400;font-style:normal}

.katex{font:normal 1.21em KaTeX_Main,Times New Roman,serif;line-height:1.2;text-indent:0;text-rendering:auto}
.katex *{-ms-high-contrast-adjust:none!important;border-color:currentColor}
.katex .katex-html{display:inline-block}
.katex .katex-mathml{position:absolute;clip:rect(1px,1px,1px,1px);padding:0;border:0;height:1px;width:1px;overflow:hidden}
.katex .base{position:relative;display:inline-block;white-space:nowrap;width:min-content}
.katex .strut{display:inline-block}
.katex .textbf{font-weight:700}
.katex .textit{font-style:italic}
.katex .textrm{font-family:KaTeX_Main}
.katex .textsf{font-family:KaTeX_SansSerif}
.katex .texttt{font-family:KaTeX_Typewriter}
.katex .mathnormal{font-family:KaTeX_Math;font-style:italic}
.katex .mathit{font-family:KaTeX_Main;font-style:italic}
.katex .mathrm{font-style:normal}
.katex .mathbf{font-family:KaTeX_Main;font-weight:700}
.katex .boldsymbol{font-family:KaTeX_Math;font-weight:700;font-style:italic}
.katex .amsrm{font-family:KaTeX_AMS}
.katex .mathbb,.katex .textbb{font-family:KaTeX_AMS}
.katex .mathcal{font-family:KaTeX_Caligraphic}
.katex .mathfrak,.katex .textfrak{font-family:KaTeX_Fraktur}
.katex .mathtt{font-family:KaTeX_Typewriter}
.katex .mathscr,.katex .textscr{font-family:KaTeX_Script}
.katex .mathsf,.katex .textsf{font-family:KaTeX_SansSerif}
.katex .mathboldsf,.katex .textboldsf{font-family:KaTeX_SansSerif;font-weight:700}
.katex .mathitsf,.katex .textitsf{font-family:KaTeX_SansSerif;font-style:italic}
.katex .mainrm{font-family:KaTeX_Main;font-style:normal}
.katex .vlist-t{display:inline-table;table-layout:fixed;border-collapse:collapse}
.katex .vlist-r{display:table-row}
.katex .vlist{display:table-cell;vertical-align:bottom;position:relative}
.katex .vlist>span{display:block;height:0;position:relative}
.katex .vlist>span>span{display:inline-block}
.katex .vlist>span>.pstrut{overflow:hidden;width:0}
.katex .vlist-t2{margin-right:-2px}
.katex .vlist-s{display:table-cell;vertical-align:bottom;font-size:1px;width:2px;min-width:2px}
.katex .vbox{display:inline-flex;flex-direction:column;align-items:baseline}
.katex .hbox{display:inline-flex;flex-direction:row;width:100%}
.katex .thinbox{display:inline-flex;flex-direction:row;width:0;max-width:0}
.katex .msupsub{text-align:left}
.katex .mfrac>span>span{text-align:center}
.katex .mfrac .frac-line{display:inline-block;width:100%;border-bottom-style:solid}
.katex .mfrac .frac-line,.katex .overline .overline-line,.katex .underline .underline-line,.katex .hline,.katex .hdashline,.katex .rule{min-height:1px}
.katex .mspace{display:inline-block}
.katex .llap,.katex .rlap,.katex .clap{width:0;position:relative}
.katex .llap>.inner,.katex .rlap>.inner,.katex .clap>.inner{position:absolute}
.katex .llap>.fix,.katex .rlap>.fix,.katex .clap>.fix{display:inline-block}
.katex .llap>.inner{right:0}
.katex .rlap>.inner,.katex .clap>.inner{left:0}
.katex .clap>.inner>span{margin-left:-50%;margin-right:50%}
.katex .rule{display:inline-block;border:solid 0;position:relative}
.katex .overline .overline-line,.katex .underline .underline-line,.katex .hline{display:inline-block;width:100%;border-bottom-style:solid}
.katex .hdashline{display:inline-block;width:100%;border-bottom-style:dashed}
.katex .sqrt>.root{margin-left:.27777778em;margin-right:-.55555556em}
.katex .sizing,.katex .fontsize-ensurer{display:inline-block}
.katex .sizing.reset-size1.size1{font-size:1em}
.katex .sizing.reset-size1.size2{font-size:1.2em}
.katex .sizing.reset-size1.size3{font-size:1.4em}
.katex .sizing.reset-size1.size4{font-size:1.6em}
.katex .sizing.reset-size1.size5{font-size:1.8em}
.katex .sizing.reset-size1.size6{font-size:2em}
.katex .sizing.reset-size1.size7{font-size:2.4em}
.katex .sizing.reset-size1.size8{font-size:2.88em}
.katex .sizing.reset-size1.size9{font-size:3.456em}
.katex .sizing.reset-size1.size10{font-size:4.148em}
.katex .sizing.reset-size1.size11{font-size:4.976em}
.katex .sizing.reset-size6.size1{font-size:.5em}
.katex .sizing.reset-size6.size2{font-size:.6em}
.katex .sizing.reset-size6.size3{font-size:.7em}
.katex .sizing.reset-size6.size4{font-size:.8em}
.katex .sizing.reset-size6.size5{font-size:.9em}
.katex .sizing.reset-size6.size6{font-size:1em}
.katex .sizing.reset-size6.size7{font-size:1.2em}
.katex .sizing.reset-size6.size8{font-size:1.44em}
.katex .sizing.reset-size6.size9{font-size:1.728em}
.katex .sizing.reset-size6.size10{font-size:2.074em}
.katex .sizing.reset-size6.size11{font-size:2.488em}
.katex .delimsizing.size1{font-family:KaTeX_Size1}
.katex .delimsizing.size2{font-family:KaTeX_Size2}
.katex .delimsizing.size3{font-family:KaTeX_Size3}
.katex .delimsizing.size4{font-family:KaTeX_Size4}
.katex .delimsizing.mult .delim-size1>span{font-family:KaTeX_Size1}
.katex .delimsizing.mult .delim-size4>span{font-family:KaTeX_Size4}
.katex .nulldelimiter{display:inline-block;width:.12em}
.katex .delimcenter,.katex .op-symbol{position:relative}
.katex .op-symbol.small-op{font-family:KaTeX_Size1}
.katex .op-symbol.large-op{font-family:KaTeX_Size2}
.katex .op-limits>.vlist-t{text-align:center}
.katex .accent>.vlist-t{text-align:center}
.katex .accent .accent-body{position:relative}
.katex .accent .accent-body:not(.accent-full){width:0}
.katex .overlay{display:block}
.katex .mtable .vertical-separator{display:inline-block;min-width:1px}
.katex .mtable .arraycolsep{display:inline-block}
.katex .mtable .col-align-c>.vlist-t{text-align:center}
.katex .mtable .col-align-l>.vlist-t{text-align:left}
.katex .mtable .col-align-r>.vlist-t{text-align:right}
.katex-display{display:block;margin:0;text-align:center}
.katex-display>.katex{display:block;text-align:center;white-space:nowrap}
.katex-display>.katex>.katex-html{display:block;position:relative}
.katex-display>.katex>.katex-html>.tag{position:absolute;right:0}
.katex-display>.katex>.katex-html>.newline{display:block}

html,body{margin:0;padding:0;background:transparent;overflow:hidden}
body{display:${bodyDisplay};width:${bodyWidth};color:${color};text-align:${bodyTextAlign};font-size:${bodyFontSize}px;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
#math-root{display:${inline ? 'inline-block' : 'block'};width:${inline ? 'auto' : '100%'};white-space:${inline ? 'nowrap' : 'normal'};background:transparent}
.fallback{font-family:-apple-system,BlinkMacSystemFont,"SF Mono",Menlo,monospace;font-size:${fallbackFontSize}px;white-space:${inline ? 'nowrap' : 'pre-wrap'};word-break:break-word;font-style:italic;opacity:0.7}
</style>
</head>
<body>
<div id="math-root">${renderedHtml}</div>
<script>
(function(){
  var root=document.getElementById('math-root');
  function post(p){if(window.ReactNativeWebView&&window.ReactNativeWebView.postMessage)window.ReactNativeWebView.postMessage(JSON.stringify(p))}
  function measure(){if(!root)return;var r=root.getBoundingClientRect();post({type:'size',width:Math.ceil(r.width||0),height:Math.ceil(r.height||0)})}
  function schedule(){requestAnimationFrame(measure);setTimeout(measure,50);setTimeout(measure,150);setTimeout(measure,350);if(document.fonts&&document.fonts.ready)document.fonts.ready.then(function(){setTimeout(measure,30);setTimeout(measure,200)})}
  schedule();
  window.addEventListener('resize',schedule);
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
  const [webViewHeight, setWebViewHeight] = useState(inline ? 24 : 40);
  const [webViewWidth, setWebViewWidth] = useState(inline ? 28 : 0);
  const [containerWidth, setContainerWidth] = useState(0);
  const [renderError, setRenderError] = useState(false);
  const measuredRef = useRef(false);

  useEffect(() => {
    measuredRef.current = false;
    setWebViewHeight(inline ? 24 : 40);
    if (inline) {
      setWebViewWidth(Math.max(28, Math.min(windowWidth * 0.75, content.length * 9 + 24)));
    }
    setRenderError(false);
  }, [content, inline, windowWidth]);

  const html = useMemo(
    () => buildKatexHtml(content, colors.foreground, inline),
    [colors.foreground, content, inline]
  );

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
            measuredRef.current = true;
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
