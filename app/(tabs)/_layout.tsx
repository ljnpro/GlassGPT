import React from "react";
import { Platform, StyleSheet, View } from "react-native";
import { Tabs } from "expo-router";
import { BlurView } from "expo-blur";
import {
  GlassView,
  isGlassEffectAPIAvailable,
  isLiquidGlassAvailable,
} from "expo-glass-effect";
import { SymbolView } from "expo-symbols";
import MaterialIcons from "@expo/vector-icons/MaterialIcons";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useColors } from "@/hooks/use-colors";

function TabIcon({
  color,
  materialName,
  size,
  symbolName,
}: {
  color: string;
  materialName: React.ComponentProps<typeof MaterialIcons>["name"];
  size: number;
  symbolName: string;
}) {
  if (Platform.OS === "ios") {
    return <SymbolView name={symbolName as never} size={size} tintColor={color} />;
  }

  return <MaterialIcons color={color} name={materialName} size={size} />;
}

function supportsNativeTabGlass(): boolean {
  return (
    Platform.OS === "ios" &&
    typeof Platform.Version === "number" &&
    Platform.Version >= 26 &&
    isLiquidGlassAvailable() &&
    isGlassEffectAPIAvailable()
  );
}

function TabBarBackground() {
  const colors = useColors();
  const isDark = colors.background.toLowerCase() === "#000000";
  const useNativeGlass = supportsNativeTabGlass();

  if (useNativeGlass) {
    return (
      <View style={StyleSheet.absoluteFill}>
        <GlassView glassEffectStyle="regular" style={StyleSheet.absoluteFill} />
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFill,
            styles.overlay,
            {
              borderTopColor: isDark ? "rgba(255,255,255,0.08)" : "rgba(60,60,67,0.12)",
              backgroundColor: isDark ? "rgba(28,28,30,0.10)" : "rgba(255,255,255,0.04)",
            },
          ]}
        />
      </View>
    );
  }

  if (Platform.OS !== "web") {
    return (
      <View style={StyleSheet.absoluteFill}>
        <BlurView
          intensity={90}
          tint={isDark ? "dark" : "light"}
          style={StyleSheet.absoluteFill}
          experimentalBlurMethod={Platform.OS === "android" ? "dimezisBlurView" : undefined}
        />
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFill,
            styles.overlay,
            {
              borderTopColor: colors.border,
              backgroundColor: isDark ? "rgba(22,22,24,0.62)" : "rgba(255,255,255,0.72)",
            },
          ]}
        />
      </View>
    );
  }

  return (
    <View
      style={[
        StyleSheet.absoluteFill,
        styles.overlay,
        {
          backgroundColor: isDark ? "rgba(22,22,24,0.72)" : "rgba(255,255,255,0.78)",
          borderTopColor: colors.border,
        },
      ]}
    >
      <View
        style={{
          ...StyleSheet.absoluteFillObject,
          backdropFilter: "blur(24px) saturate(180%)",
          WebkitBackdropFilter: "blur(24px) saturate(180%)",
        } as never}
      />
    </View>
  );
}

export default function TabLayout() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const bottomPadding = Platform.OS === "web" ? 12 : Math.max(insets.bottom, 10);
  const tabBarHeight = 58 + bottomPadding;

  return (
    <Tabs
      screenOptions={{
        animation: "shift",
        lazy: false,
        headerShown: false,
        sceneStyle: {
          backgroundColor: colors.background,
        },
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.muted,
        tabBarHideOnKeyboard: true,
        tabBarLabelStyle: {
          fontSize: 11,
          fontWeight: "700",
          marginTop: 0,
        },
        tabBarIconStyle: {
          marginTop: 2,
        },
        tabBarStyle: {
          backgroundColor: "transparent",
          borderTopWidth: 0,
          elevation: 0,
          height: tabBarHeight,
          paddingBottom: bottomPadding,
          paddingTop: 8,
          shadowOpacity: 0,
        },
        tabBarItemStyle: {
          paddingVertical: 2,
        },
        tabBarBackground: () => <TabBarBackground />,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: "Chat",
          tabBarIcon: ({ color, size }: { color: string; size: number }) => (
            <TabIcon
              color={color}
              materialName="home"
              size={size}
              symbolName="house.fill"
            />
          ),
        }}
      />
      <Tabs.Screen
        name="conversations"
        options={{
          title: "History",
          tabBarIcon: ({ color, size }: { color: string; size: number }) => (
            <TabIcon
              color={color}
              materialName="schedule"
              size={size}
              symbolName="clock.fill"
            />
          ),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: "Settings",
          tabBarIcon: ({ color, size }: { color: string; size: number }) => (
            <TabIcon
              color={color}
              materialName="settings"
              size={size}
              symbolName="gearshape.fill"
            />
          ),
        }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  overlay: {
    borderTopWidth: StyleSheet.hairlineWidth,
  },
});
