import React from "react";
import { StyleSheet, View, type ViewProps } from "react-native";
import { SafeAreaView, type Edge } from "react-native-safe-area-context";

import { useColors } from "@/hooks/use-colors";
import { cn } from "@/lib/utils";

export interface ScreenContainerProps extends ViewProps {
  edges?: Edge[];
  className?: string;
  containerClassName?: string;
  safeAreaClassName?: string;
}

export function ScreenContainer({
  children,
  edges = ["top", "left", "right"],
  className,
  containerClassName,
  safeAreaClassName,
  style,
  ...props
}: ScreenContainerProps) {
  const colors = useColors();
  const isDark = colors.background.toLowerCase() === "#000000";

  const orbPrimary = isDark ? "rgba(10,132,255,0.18)" : "rgba(0,122,255,0.14)";
  const orbSecondary = isDark ? "rgba(94,92,230,0.14)" : "rgba(88,86,214,0.11)";
  const orbWarm = isDark ? "rgba(255,159,10,0.08)" : "rgba(255,149,0,0.08)";
  const lineColor = isDark ? "rgba(255,255,255,0.03)" : "rgba(60,60,67,0.04)";

  return (
    <View
      {...props}
      className={cn("flex-1", containerClassName)}
      style={[styles.root, { backgroundColor: colors.background }]}
    >
      <View pointerEvents="none" style={StyleSheet.absoluteFill}>
        <View style={[styles.orb, styles.topOrb, { backgroundColor: orbPrimary }]} />
        <View style={[styles.orb, styles.midOrb, { backgroundColor: orbSecondary }]} />
        <View style={[styles.orb, styles.bottomOrb, { backgroundColor: orbWarm }]} />
        <View style={[styles.topLine, { backgroundColor: lineColor }]} />
        <View style={[styles.bottomLine, { backgroundColor: lineColor }]} />
      </View>

      <SafeAreaView
        edges={edges}
        className={cn("flex-1", safeAreaClassName)}
        style={style}
      >
        <View className={cn("flex-1", className)}>{children}</View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  orb: {
    position: "absolute",
    borderRadius: 9999,
  },
  topOrb: {
    width: 320,
    height: 320,
    top: -120,
    right: -120,
  },
  midOrb: {
    width: 260,
    height: 260,
    top: "26%",
    left: -130,
  },
  bottomOrb: {
    width: 300,
    height: 300,
    bottom: -150,
    right: -110,
  },
  topLine: {
    position: "absolute",
    top: 132,
    left: 16,
    right: 16,
    height: StyleSheet.hairlineWidth,
    borderRadius: 999,
  },
  bottomLine: {
    position: "absolute",
    bottom: 124,
    left: 16,
    right: 16,
    height: StyleSheet.hairlineWidth,
    borderRadius: 999,
  },
});
