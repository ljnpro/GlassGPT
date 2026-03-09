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
import { GlassView as ExpoGlassView } from "expo-glass-effect";
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

  const normalized = String(version).split(".")[0];
  const parsed = Number.parseInt(normalized, 10);

  return Number.isNaN(parsed) ? 0 : parsed;
}

function buildRadiusStyle(flattenedStyle?: ViewStyle): ViewStyle {
  const radiusStyle: ViewStyle = {
    borderRadius:
      typeof flattenedStyle?.borderRadius === "number"
        ? flattenedStyle.borderRadius
        : DEFAULT_RADIUS,
    borderTopLeftRadius:
      typeof flattenedStyle?.borderTopLeftRadius === "number"
        ? flattenedStyle.borderTopLeftRadius
        : undefined,
    borderTopRightRadius:
      typeof flattenedStyle?.borderTopRightRadius === "number"
        ? flattenedStyle.borderTopRightRadius
        : undefined,
    borderBottomLeftRadius:
      typeof flattenedStyle?.borderBottomLeftRadius === "number"
        ? flattenedStyle.borderBottomLeftRadius
        : undefined,
    borderBottomRightRadius:
      typeof flattenedStyle?.borderBottomRightRadius === "number"
        ? flattenedStyle.borderBottomRightRadius
        : undefined,
  };

  if (Platform.OS === "ios") {
    radiusStyle.borderCurve = "continuous";
  }

  return radiusStyle;
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
  const flattenedStyle = StyleSheet.flatten(style) as ViewStyle | undefined;
  const radiusStyle = buildRadiusStyle(flattenedStyle);
  const resolvedTint: BlurTint = tint ?? (isDark ? "dark" : "light");
  const canUseGlass = Platform.OS === "ios" && getIOSMajorVersion(Platform.Version) >= 26;

  const borderColor = isDark ? "rgba(255,255,255,0.12)" : "rgba(60,60,67,0.14)";
  const shadowStyle: ViewStyle = {
    shadowColor: "#000000",
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: isDark ? 0.3 : 0.08,
    shadowRadius: isDark ? 20 : 24,
    elevation: 10,
  };

  const glassOverlayColor = isDark ? "rgba(255,255,255,0.025)" : "rgba(255,255,255,0.18)";
  const blurOverlayColor = isDark ? "rgba(255,255,255,0.02)" : "rgba(255,255,255,0.24)";
  const fallbackBackgroundColor = isDark
    ? "rgba(28,28,30,0.72)"
    : "rgba(255,255,255,0.74)";

  const nativeWindProps = className ? { className } : {};

  if (canUseGlass) {
    try {
      return (
        <NativeContainer
          {...nativeWindProps}
          {...rest}
          style={[
            styles.container,
            radiusStyle,
            shadowStyle,
            {
              borderColor,
              backgroundColor: fallbackBackgroundColor,
            },
            style,
          ]}
        >
          <ExpoGlassView
            pointerEvents="none"
            style={[StyleSheet.absoluteFill, radiusStyle]}
            glassEffectStyle="regular"
          />
          <View
            pointerEvents="none"
            style={[
              StyleSheet.absoluteFill,
              radiusStyle,
              styles.overlay,
              { backgroundColor: glassOverlayColor },
            ]}
          />
          {children}
        </NativeContainer>
      );
    } catch {
      // Fallback handled below.
    }
  }

  if (Platform.OS !== "web") {
    return (
      <NativeContainer
        {...nativeWindProps}
        {...rest}
        style={[
          styles.container,
          radiusStyle,
          shadowStyle,
          {
            borderColor,
            backgroundColor: fallbackBackgroundColor,
          },
          style,
        ]}
      >
        <BlurView
          pointerEvents="none"
          intensity={intensity}
          tint={resolvedTint}
          style={[StyleSheet.absoluteFill, radiusStyle]}
          {...(Platform.OS === "android"
            ? { experimentalBlurMethod: "dimezisBlurView" as const }
            : {})}
        />
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFill,
            radiusStyle,
            styles.overlay,
            { backgroundColor: blurOverlayColor },
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
        styles.container,
        radiusStyle,
        shadowStyle,
        {
          borderColor,
          backgroundColor: fallbackBackgroundColor,
        },
        styles.webGlass,
        style,
      ]}
    >
      {children}
    </NativeContainer>
  );
}

const styles = StyleSheet.create({
  container: {
    position: "relative",
    overflow: "hidden",
    borderRadius: DEFAULT_RADIUS,
    borderWidth: StyleSheet.hairlineWidth,
  },
  overlay: {
    opacity: 1,
  },
  webGlass: {
    backdropFilter: "blur(28px) saturate(180%)",
    WebkitBackdropFilter: "blur(28px) saturate(180%)",
  } as ViewStyle,
});
