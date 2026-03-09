import React, { type ReactNode } from "react";
import {
  Platform,
  StyleSheet,
  View,
  type StyleProp,
  type ViewProps,
  type ViewStyle,
} from "react-native";
import { BlurView } from "expo-blur";
import {
  GlassView,
  isGlassEffectAPIAvailable,
  isLiquidGlassAvailable,
} from "expo-glass-effect";

import { useColors } from "@/hooks/use-colors";

type BlurTint = "light" | "dark" | "default";

const DEFAULT_RADIUS = 22;
const NativeContainer = View as unknown as React.ComponentType<any>;

export interface GlassCardProps extends Omit<ViewProps, "style" | "children"> {
  children?: ReactNode;
  className?: string;
  style?: StyleProp<ViewStyle>;
  intensity?: number;
  tint?: BlurTint;
}

function getIOSMajorVersion(version: string | number): number {
  if (typeof version === "number") {
    return version;
  }

  const parsed = Number.parseInt(String(version).split(".")[0] ?? "0", 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function buildRadiusStyle(style?: ViewStyle): ViewStyle {
  const radiusStyle: ViewStyle = {
    borderRadius: typeof style?.borderRadius === "number" ? style.borderRadius : DEFAULT_RADIUS,
  };

  if (typeof style?.borderTopLeftRadius === "number") {
    radiusStyle.borderTopLeftRadius = style.borderTopLeftRadius;
  }
  if (typeof style?.borderTopRightRadius === "number") {
    radiusStyle.borderTopRightRadius = style.borderTopRightRadius;
  }
  if (typeof style?.borderBottomLeftRadius === "number") {
    radiusStyle.borderBottomLeftRadius = style.borderBottomLeftRadius;
  }
  if (typeof style?.borderBottomRightRadius === "number") {
    radiusStyle.borderBottomRightRadius = style.borderBottomRightRadius;
  }

  if (Platform.OS === "ios") {
    radiusStyle.borderCurve = "continuous";
  }

  return radiusStyle;
}

function sanitizeStyle(flattenedStyle?: ViewStyle): ViewStyle {
  if (!flattenedStyle) {
    return {};
  }

  const nextStyle = { ...flattenedStyle };
  delete nextStyle.backgroundColor;
  delete nextStyle.opacity;
  delete nextStyle.overflow;

  return nextStyle;
}

function canUseNativeLiquidGlass(): boolean {
  return (
    Platform.OS === "ios" &&
    getIOSMajorVersion(Platform.Version) >= 26 &&
    isLiquidGlassAvailable() &&
    isGlassEffectAPIAvailable()
  );
}

export function GlassCard({
  children,
  className,
  style,
  intensity = 72,
  tint,
  ...rest
}: GlassCardProps) {
  const colors = useColors();
  const isDark = colors.background.toLowerCase() === "#000000";

  const flattenedStyle = (StyleSheet.flatten(style) ?? {}) as ViewStyle;
  const sanitizedStyle = sanitizeStyle(flattenedStyle);
  const radiusStyle = buildRadiusStyle(flattenedStyle);
  const resolvedTint: BlurTint = tint ?? (isDark ? "dark" : "light");
  const useNativeGlass = canUseNativeLiquidGlass();

  const resolvedBorderWidth =
    typeof flattenedStyle.borderWidth === "number"
      ? flattenedStyle.borderWidth
      : StyleSheet.hairlineWidth;

  const resolvedBorderColor =
    typeof flattenedStyle.borderColor === "string"
      ? flattenedStyle.borderColor
      : isDark
        ? "rgba(255,255,255,0.10)"
        : "rgba(60,60,67,0.14)";

  const shadowStyle: ViewStyle = {
    shadowColor: "#000000",
    shadowOffset: { width: 0, height: isDark ? 10 : 12 },
    shadowOpacity: isDark ? 0.28 : 0.08,
    shadowRadius: isDark ? 20 : 24,
    elevation: 10,
  };

  const fallbackBackgroundColor = isDark
    ? "rgba(28,28,30,0.78)"
    : "rgba(255,255,255,0.78)";
  const blurOverlayColor = isDark ? "rgba(255,255,255,0.018)" : "rgba(255,255,255,0.16)";
  const nativeOverlayColor = isDark ? "rgba(28,28,30,0.14)" : "rgba(255,255,255,0.06)";

  const nativeWindProps = className ? { className } : {};

  if (useNativeGlass) {
    return (
      <NativeContainer
        {...nativeWindProps}
        {...rest}
        style={[
          styles.base,
          shadowStyle,
          sanitizedStyle,
          radiusStyle,
          {
            backgroundColor: "transparent",
            borderColor: resolvedBorderColor,
            borderWidth: resolvedBorderWidth,
            overflow: "visible",
          },
        ]}
      >
        <GlassView
          glassEffectStyle="regular"
          style={[StyleSheet.absoluteFillObject, radiusStyle]}
        />
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFillObject,
            radiusStyle,
            {
              backgroundColor: nativeOverlayColor,
            },
          ]}
        />
        {children}
      </NativeContainer>
    );
  }

  if (Platform.OS !== "web") {
    return (
      <NativeContainer
        {...nativeWindProps}
        {...rest}
        style={[
          styles.base,
          shadowStyle,
          sanitizedStyle,
          radiusStyle,
          {
            backgroundColor: fallbackBackgroundColor,
            borderColor: resolvedBorderColor,
            borderWidth: resolvedBorderWidth,
            overflow: "hidden",
          },
        ]}
      >
        <BlurView
          pointerEvents="none"
          intensity={intensity}
          tint={resolvedTint}
          style={StyleSheet.absoluteFillObject}
          {...(Platform.OS === "android"
            ? { experimentalBlurMethod: "dimezisBlurView" as const }
            : {})}
        />
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFillObject,
            {
              backgroundColor: blurOverlayColor,
            },
          ]}
        />
        {children}
      </NativeContainer>
    );
  }

  return (
    <NativeContainer
      {...nativeWindProps}
      {...rest}
      style={[
        styles.base,
        shadowStyle,
        sanitizedStyle,
        radiusStyle,
        styles.webGlass,
        {
          backgroundColor: fallbackBackgroundColor,
          borderColor: resolvedBorderColor,
          borderWidth: resolvedBorderWidth,
          overflow: "hidden",
        },
      ]}
    >
      {children}
    </NativeContainer>
  );
}

const styles = StyleSheet.create({
  base: {
    position: "relative",
    borderRadius: DEFAULT_RADIUS,
  },
  webGlass: {
    backdropFilter: "blur(28px) saturate(180%)",
    WebkitBackdropFilter: "blur(28px) saturate(180%)",
  } as ViewStyle,
});
