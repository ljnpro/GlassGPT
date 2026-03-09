import React from 'react';
import { View, Platform, StyleSheet, ViewStyle } from 'react-native';
import { BlurView } from 'expo-blur';
import { useColorScheme } from '@/hooks/use-color-scheme';

interface GlassCardProps {
  children: React.ReactNode;
  style?: ViewStyle;
  intensity?: number;
  className?: string;
}

let GlassView: any = null;
let isGlassEffectAPIAvailable: (() => boolean) | null = null;

try {
  const glassModule = require('expo-glass-effect');
  GlassView = glassModule.GlassView;
  isGlassEffectAPIAvailable = glassModule.isGlassEffectAPIAvailable;
} catch {}

export function GlassCard({ children, style, intensity = 80, className }: GlassCardProps) {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  // Try native Liquid Glass on iOS 26+
  if (Platform.OS === 'ios' && GlassView && isGlassEffectAPIAvailable?.()) {
    return (
      <GlassView style={[styles.glass, style]} glassEffectStyle="regular">
        {children}
      </GlassView>
    );
  }

  // Fallback to BlurView on native platforms
  if (Platform.OS !== 'web') {
    return (
      <BlurView
        intensity={intensity}
        tint={isDark ? 'dark' : 'light'}
        style={[styles.blur, style]}
        experimentalBlurMethod={Platform.OS === 'android' ? 'dimezisBlurView' : undefined}
      >
        {children}
      </BlurView>
    );
  }

  // Web fallback with CSS backdrop-filter
  const webStyle: any = {
    backgroundColor: isDark ? 'rgba(28,28,30,0.75)' : 'rgba(255,255,255,0.75)',
    backdropFilter: 'blur(20px) saturate(180%)',
    WebkitBackdropFilter: 'blur(20px) saturate(180%)',
  };
  return (
    <View style={[styles.webGlass, webStyle, style]}>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  glass: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  blur: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  webGlass: {
    borderRadius: 16,
    overflow: 'hidden',
  },
});
