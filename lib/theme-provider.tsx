import React, { createContext, useCallback, useContext, useEffect, useMemo } from "react";
import { Appearance, Platform, View, useColorScheme as useSystemColorScheme } from "react-native";
import { colorScheme as nativewindColorScheme, vars } from "nativewind";

import { SchemeColors, type ColorScheme } from "@/constants/theme";
import { useChatStore } from "@/lib/chat-store";
import type { AppTheme } from "@/lib/types";

type ThemeContextValue = {
  theme: AppTheme;
  resolvedColorScheme: ColorScheme;
  setTheme: (theme: AppTheme) => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

function resolveColorScheme(theme: AppTheme, systemScheme: ColorScheme): ColorScheme {
  return theme === "system" ? systemScheme : theme;
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = (useSystemColorScheme() ?? "light") as ColorScheme;
  const { state, dispatch } = useChatStore();

  const theme = state.settings.theme;
  const resolvedColorScheme = resolveColorScheme(theme, systemScheme);

  const applyScheme = useCallback((scheme: ColorScheme) => {
    nativewindColorScheme.set(scheme);
    Appearance.setColorScheme?.(scheme);

    if (Platform.OS === "web" && typeof document !== "undefined") {
      const root = document.documentElement;
      const palette = SchemeColors[scheme];

      root.dataset.theme = scheme;
      root.classList.toggle("dark", scheme === "dark");

      Object.entries(palette).forEach(([token, value]) => {
        root.style.setProperty(`--color-${token}`, value);
      });

      root.style.backgroundColor = palette.background;
      root.style.color = palette.foreground;
    }
  }, []);

  useEffect(() => {
    applyScheme(resolvedColorScheme);
  }, [applyScheme, resolvedColorScheme]);

  const setTheme = useCallback(
    (nextTheme: AppTheme) => {
      dispatch({
        type: "UPDATE_SETTINGS",
        settings: { theme: nextTheme },
      });
    },
    [dispatch]
  );

  const themeVariables = useMemo(
    () =>
      vars({
        "color-primary": SchemeColors[resolvedColorScheme].primary,
        "color-background": SchemeColors[resolvedColorScheme].background,
        "color-surface": SchemeColors[resolvedColorScheme].surface,
        "color-foreground": SchemeColors[resolvedColorScheme].foreground,
        "color-muted": SchemeColors[resolvedColorScheme].muted,
        "color-border": SchemeColors[resolvedColorScheme].border,
        "color-success": SchemeColors[resolvedColorScheme].success,
        "color-warning": SchemeColors[resolvedColorScheme].warning,
        "color-error": SchemeColors[resolvedColorScheme].error,
      }),
    [resolvedColorScheme]
  );

  const value = useMemo<ThemeContextValue>(
    () => ({
      theme,
      resolvedColorScheme,
      setTheme,
    }),
    [resolvedColorScheme, setTheme, theme]
  );

  return (
    <ThemeContext.Provider value={value}>
      <View
        style={[
          {
            flex: 1,
            backgroundColor: SchemeColors[resolvedColorScheme].background,
          },
          themeVariables,
        ]}
      >
        {children}
      </View>
    </ThemeContext.Provider>
  );
}

export function useThemeContext(): ThemeContextValue {
  const context = useContext(ThemeContext);

  if (!context) {
    throw new Error("useThemeContext must be used within ThemeProvider");
  }

  return context;
}
