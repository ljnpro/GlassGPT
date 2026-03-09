import React, { useState, useCallback } from 'react';
import { View, Text, Pressable, Modal, StyleSheet, Platform } from 'react-native';
import * as Haptics from 'expo-haptics';
import { useColors } from '@/hooks/use-colors';
import { GlassCard } from './glass-card';
import { ModelId, ReasoningEffort, MODELS } from '@/lib/types';

interface ModelSelectorProps {
  model: ModelId;
  effort: ReasoningEffort;
  onModelChange: (model: ModelId) => void;
  onEffortChange: (effort: ReasoningEffort) => void;
}

const EFFORT_LABELS: Record<ReasoningEffort, string> = {
  none: 'None',
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  xhigh: 'xHigh',
};

const EFFORT_COLORS: Record<ReasoningEffort, string> = {
  none: '#8E8E93',
  low: '#34C759',
  medium: '#FF9500',
  high: '#FF3B30',
  xhigh: '#AF52DE',
};

export function ModelSelector({ model, effort, onModelChange, onEffortChange }: ModelSelectorProps) {
  const colors = useColors();
  const [showPicker, setShowPicker] = useState(false);

  const currentModel = MODELS.find((m) => m.id === model) || MODELS[1];

  const handleModelSelect = useCallback(
    (m: ModelId) => {
      if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onModelChange(m);
      const newModel = MODELS.find((mod) => mod.id === m)!;
      if (!newModel.reasoningEfforts.includes(effort)) {
        onEffortChange(newModel.defaultEffort);
      }
    },
    [effort, onModelChange, onEffortChange]
  );

  const handleEffortSelect = useCallback(
    (e: ReasoningEffort) => {
      if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onEffortChange(e);
      setShowPicker(false);
    },
    [onEffortChange]
  );

  return (
    <>
      <Pressable
        onPress={() => {
          if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
          setShowPicker(true);
        }}
        style={({ pressed }) => [
          styles.selectorButton,
          {
            backgroundColor: pressed
              ? (colors as any).surface || '#f5f5f5'
              : 'transparent',
          },
        ]}
      >
        <View style={styles.selectorContent}>
          <Text style={[styles.modelName, { color: colors.foreground }]} numberOfLines={1}>
            {currentModel.label}
          </Text>
          <View style={[styles.effortBadge, { backgroundColor: EFFORT_COLORS[effort] + '20' }]}>
            <Text style={[styles.effortText, { color: EFFORT_COLORS[effort] }]}>
              {EFFORT_LABELS[effort]}
            </Text>
          </View>
          <Text style={{ color: colors.muted, fontSize: 12 }}>▼</Text>
        </View>
      </Pressable>

      <Modal visible={showPicker} transparent animationType="fade" onRequestClose={() => setShowPicker(false)}>
        <Pressable style={styles.overlay} onPress={() => setShowPicker(false)}>
          <View style={styles.pickerContainer}>
            <Pressable onPress={(e) => e.stopPropagation()}>
              <GlassCard style={{ ...styles.pickerCard, borderColor: colors.border }}>
                {/* Model Selection */}
                <Text style={[styles.sectionTitle, { color: colors.muted }]}>MODEL</Text>
                <View style={styles.modelRow}>
                  {MODELS.map((m) => (
                    <Pressable
                      key={m.id}
                      onPress={() => handleModelSelect(m.id)}
                      style={({ pressed }) => [
                        styles.modelChip,
                        {
                          backgroundColor: model === m.id ? colors.primary : colors.surface,
                          borderColor: model === m.id ? colors.primary : colors.border,
                          opacity: pressed ? 0.8 : 1,
                        },
                      ]}
                    >
                      <Text
                        style={[
                          styles.modelChipText,
                          { color: model === m.id ? '#FFFFFF' : colors.foreground },
                        ]}
                      >
                        {m.label}
                      </Text>
                    </Pressable>
                  ))}
                </View>

                {/* Reasoning Effort */}
                <Text style={[styles.sectionTitle, { color: colors.muted, marginTop: 20 }]}>
                  REASONING EFFORT
                </Text>
                <View style={styles.effortRow}>
                  {currentModel.reasoningEfforts.map((e) => (
                    <Pressable
                      key={e}
                      onPress={() => handleEffortSelect(e)}
                      style={({ pressed }) => [
                        styles.effortChip,
                        {
                          backgroundColor: effort === e ? EFFORT_COLORS[e] : colors.surface,
                          borderColor: effort === e ? EFFORT_COLORS[e] : colors.border,
                          opacity: pressed ? 0.8 : 1,
                        },
                      ]}
                    >
                      <Text
                        style={[
                          styles.effortChipText,
                          { color: effort === e ? '#FFFFFF' : colors.foreground },
                        ]}
                      >
                        {EFFORT_LABELS[e]}
                      </Text>
                    </Pressable>
                  ))}
                </View>

                {/* Description */}
                <View style={[styles.descriptionBox, { backgroundColor: colors.surface }]}>
                  <Text style={{ color: colors.muted, fontSize: 13, lineHeight: 18 }}>
                    {model === 'gpt-5.4-pro'
                      ? 'GPT-5.4 Pro — Most capable model for complex reasoning, analysis, and creative tasks.'
                      : 'GPT-5.4 — Fast and efficient for everyday tasks with flexible reasoning levels.'}
                  </Text>
                </View>
              </GlassCard>
            </Pressable>
          </View>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  selectorButton: {
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  selectorContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  modelName: {
    fontSize: 16,
    fontWeight: '700',
  },
  effortBadge: {
    borderRadius: 6,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  effortText: {
    fontSize: 11,
    fontWeight: '700',
  },
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.4)',
    justifyContent: 'flex-start',
    paddingTop: 100,
    paddingHorizontal: 20,
  },
  pickerContainer: {
    width: '100%',
    maxWidth: 400,
    alignSelf: 'center',
  },
  pickerCard: {
    padding: 20,
    borderWidth: 1,
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
    marginBottom: 10,
  },
  modelRow: {
    flexDirection: 'row',
    gap: 10,
  },
  modelChip: {
    flex: 1,
    borderRadius: 12,
    borderWidth: 1,
    paddingVertical: 12,
    alignItems: 'center',
  },
  modelChipText: {
    fontSize: 14,
    fontWeight: '600',
  },
  effortRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  effortChip: {
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  effortChipText: {
    fontSize: 13,
    fontWeight: '600',
  },
  descriptionBox: {
    borderRadius: 10,
    padding: 12,
    marginTop: 16,
  },
});
