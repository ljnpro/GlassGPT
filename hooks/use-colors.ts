import { Colors, type ColorScheme, type ThemeColorPalette } from "@/constants/theme";
import { useThemeContext } from "@/lib/theme-provider";

/**
 * Returns the active palette resolved by ThemeProvider.
 * You can still override it manually by passing a scheme.
 */
export function useColors(colorSchemeOverride?: ColorScheme): ThemeColorPalette {
  const { resolvedColorScheme } = useThemeContext();
  const scheme = (colorSchemeOverride ?? resolvedColorScheme ?? "light") as ColorScheme;
  return Colors[scheme];
}
