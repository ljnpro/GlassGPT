import React, { useCallback, useMemo, useState } from "react";
import {
  FlatList,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  type ListRenderItem,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import * as Haptics from "expo-haptics";

import { useColors } from "@/hooks/use-colors";
import { useChatStore } from "@/lib/chat-store";
import { MODELS, type ModelConfig, type ModelId, type ReasoningEffort } from "@/lib/types";
import { GlassCard } from "./glass-card";
import { IconSymbol } from "@/components/ui/icon-symbol";

interface ModelSelectorProps {
  model?: ModelId;
  effort?: ReasoningEffort;
  onModelChange?: (model: ModelId) => void;
  onEffortChange?: (effort: ReasoningEffort) => void;
}

const EFFORT_LABELS: Record<ReasoningEffort, string> = {
  none: "None",
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "xHigh",
};

const MODEL_SUBTITLES: Record<ModelId, string> = {
  "gpt-5.4": "Fast, flexible, and ideal for most everyday conversations.",
  "gpt-5.4-pro": "Highest capability for deep reasoning, analysis, and polished writing.",
};

const MODEL_FOOTERS: Record<ModelId, string> = {
  "gpt-5.4":
    "Balanced speed and quality. Great for daily use, brainstorming, and general problem solving.",
  "gpt-5.4-pro":
    "Best when you want maximum depth, stronger analysis, and more deliberate reasoning.",
};

export function ModelSelector({
  model,
  effort,
  onModelChange,
  onEffortChange,
}: ModelSelectorProps) {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const {
    currentModel: storeCurrentModel,
    currentEffort: storeCurrentEffort,
    setCurrentModel,
    setCurrentEffort,
  } = useChatStore();

  const [visible, setVisible] = useState(false);

  const isDark = colors.background.toLowerCase() === "#000000";
  const selectedModel = model ?? storeCurrentModel;
  const selectedEffort = effort ?? storeCurrentEffort;
  const applyModelChange = onModelChange ?? setCurrentModel;
  const applyEffortChange = onEffortChange ?? setCurrentEffort;

  const selectedModelConfig = useMemo<ModelConfig>(() => {
    return MODELS.find((item) => item.id === selectedModel) ?? MODELS[0];
  }, [selectedModel]);

  const triggerBackgroundColor = isDark
    ? "rgba(255,255,255,0.08)"
    : "rgba(120,120,128,0.12)";
  const triggerBorderColor = isDark
    ? "rgba(255,255,255,0.08)"
    : "rgba(60,60,67,0.10)";
  const selectedRowBackgroundColor = isDark
    ? "rgba(10,132,255,0.18)"
    : "rgba(0,122,255,0.10)";
  const helperBackgroundColor = isDark
    ? "rgba(255,255,255,0.05)"
    : "rgba(120,120,128,0.10)";
  const effortBadgeBackgroundColor = isDark
    ? "rgba(10,132,255,0.18)"
    : "rgba(0,122,255,0.12)";

  const playSelectionHaptic = useCallback(async () => {
    if (Platform.OS !== "web") {
      await Haptics.selectionAsync();
    }
  }, []);

  const openModal = useCallback(async () => {
    await playSelectionHaptic();
    setVisible(true);
  }, [playSelectionHaptic]);

  const closeModal = useCallback(() => {
    setVisible(false);
  }, []);

  const handleSelectModel = useCallback(
    async (nextModel: ModelId) => {
      await playSelectionHaptic();

      const nextConfig = MODELS.find((item) => item.id === nextModel) ?? MODELS[0];
      applyModelChange(nextModel);

      if (!nextConfig.reasoningEfforts.includes(selectedEffort)) {
        applyEffortChange(nextConfig.defaultEffort);
      }

      closeModal();
    },
    [applyEffortChange, applyModelChange, closeModal, playSelectionHaptic, selectedEffort]
  );

  const handleSelectEffort = useCallback(
    async (nextEffort: ReasoningEffort) => {
      await playSelectionHaptic();
      applyEffortChange(nextEffort);
      closeModal();
    },
    [applyEffortChange, closeModal, playSelectionHaptic]
  );

  const renderModelItem: ListRenderItem<ModelConfig> = useCallback(
    ({ item }) => {
      const isSelected = item.id === selectedModel;

      return (
        <Pressable
          onPress={() => {
            void handleSelectModel(item.id);
          }}
          style={({ pressed }) => [
            styles.modelRowButton,
            {
              backgroundColor: isSelected ? selectedRowBackgroundColor : colors.surface,
              borderColor: isSelected ? colors.primary : colors.border,
              opacity: pressed ? 0.92 : 1,
            },
          ]}
        >
          <View style={styles.modelRowContent}>
            <View style={styles.modelTextColumn}>
              <Text style={[styles.modelTitle, { color: colors.foreground }]}>{item.label}</Text>
              <Text style={[styles.modelSubtitle, { color: colors.muted }]}>
                {MODEL_SUBTITLES[item.id]}
              </Text>
            </View>
            <View style={styles.modelTrailing}>
              {isSelected ? (
                <IconSymbol name="checkmark.circle.fill" size={22} color={colors.primary} />
              ) : (
                <IconSymbol name="chevron.right" size={18} color={colors.muted} />
              )}
            </View>
          </View>
        </Pressable>
      );
    },
    [
      colors.border,
      colors.foreground,
      colors.muted,
      colors.primary,
      colors.surface,
      handleSelectModel,
      selectedModel,
      selectedRowBackgroundColor,
    ]
  );

  const renderEffortItem: ListRenderItem<ReasoningEffort> = useCallback(
    ({ item }) => {
      const isSelected = item === selectedEffort;

      return (
        <Pressable
          onPress={() => {
            void handleSelectEffort(item);
          }}
          style={({ pressed }) => [
            styles.effortChip,
            {
              backgroundColor: isSelected ? colors.primary : colors.surface,
              borderColor: isSelected ? colors.primary : colors.border,
              opacity: pressed ? 0.9 : 1,
            },
          ]}
        >
          <Text
            style={[
              styles.effortChipText,
              { color: isSelected ? "#FFFFFF" : colors.foreground },
            ]}
          >
            {EFFORT_LABELS[item]}
          </Text>
        </Pressable>
      );
    },
    [
      colors.border,
      colors.foreground,
      colors.primary,
      colors.surface,
      handleSelectEffort,
      selectedEffort,
    ]
  );

  return (
    <>
      <Pressable
        onPress={() => {
          void openModal();
        }}
        style={({ pressed }) => [
          styles.trigger,
          {
            backgroundColor: triggerBackgroundColor,
            borderColor: triggerBorderColor,
            opacity: pressed ? 0.92 : 1,
          },
        ]}
      >
        <View style={styles.triggerContent}>
          <Text style={[styles.triggerTitle, { color: colors.foreground }]} numberOfLines={1}>
            {selectedModelConfig.label}
          </Text>
          <View
            style={[
              styles.triggerEffortBadge,
              { backgroundColor: effortBadgeBackgroundColor },
            ]}
          >
            <Text style={[styles.triggerEffortText, { color: colors.primary }]}>
              {EFFORT_LABELS[selectedEffort]}
            </Text>
          </View>
          <IconSymbol name="chevron.down" size={18} color={colors.muted} />
        </View>
      </Pressable>

      <Modal
        visible={visible}
        transparent
        animationType="fade"
        statusBarTranslucent
        presentationStyle="overFullScreen"
        onRequestClose={closeModal}
      >
        <Pressable style={styles.backdrop} onPress={closeModal}>
          <View style={[styles.modalContainer, { paddingTop: insets.top + 48 }]}>
            <Pressable
              onPress={(event) => {
                event.stopPropagation();
              }}
              style={styles.cardWrapper}
            >
              <GlassCard
                style={[
                  styles.modalCard,
                  {
                    borderColor: isDark
                      ? "rgba(255,255,255,0.10)"
                      : "rgba(60,60,67,0.12)",
                  },
                ]}
              >
                <View style={styles.dragHandleWrap}>
                  <View
                    style={[
                      styles.dragHandle,
                      {
                        backgroundColor: isDark
                          ? "rgba(255,255,255,0.18)"
                          : "rgba(60,60,67,0.18)",
                      },
                    ]}
                  />
                </View>

                <View style={styles.headerRow}>
                  <View style={styles.headerTextColumn}>
                    <Text style={[styles.headerTitle, { color: colors.foreground }]}>
                      Model & Reasoning
                    </Text>
                    <Text style={[styles.headerSubtitle, { color: colors.muted }]}>
                      Choose the model and how much effort it should spend thinking.
                    </Text>
                  </View>

                  <Pressable
                    onPress={closeModal}
                    style={({ pressed }) => [
                      styles.closeButton,
                      {
                        backgroundColor: helperBackgroundColor,
                        opacity: pressed ? 0.84 : 1,
                      },
                    ]}
                  >
                    <IconSymbol name="xmark.circle.fill" size={20} color={colors.muted} />
                  </Pressable>
                </View>

                <Text style={[styles.sectionLabel, { color: colors.muted }]}>MODEL</Text>

                <FlatList
                  data={MODELS}
                  renderItem={renderModelItem}
                  keyExtractor={(item) => item.id}
                  scrollEnabled={false}
                  ItemSeparatorComponent={() => <View style={styles.modelSeparator} />}
                />

                <Text
                  style={[
                    styles.sectionLabel,
                    styles.effortSectionLabel,
                    { color: colors.muted },
                  ]}
                >
                  REASONING EFFORT
                </Text>

                <FlatList
                  data={selectedModelConfig.reasoningEfforts}
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  keyExtractor={(item) => item}
                  renderItem={renderEffortItem}
                  contentContainerStyle={styles.effortListContent}
                  ItemSeparatorComponent={() => <View style={styles.effortSeparator} />}
                />

                <View
                  style={[
                    styles.helperCard,
                    {
                      backgroundColor: helperBackgroundColor,
                      borderColor: isDark
                        ? "rgba(255,255,255,0.06)"
                        : "rgba(60,60,67,0.08)",
                    },
                  ]}
                >
                  <Text style={[styles.helperTitle, { color: colors.foreground }]}>
                    {selectedModelConfig.label}
                  </Text>
                  <Text style={[styles.helperText, { color: colors.muted }]}>
                    {MODEL_FOOTERS[selectedModelConfig.id]}
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
  trigger: {
    minHeight: 40,
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingVertical: 7,
    justifyContent: "center",
  },
  triggerContent: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  triggerTitle: {
    fontSize: 15,
    fontWeight: "700",
    letterSpacing: -0.2,
  },
  triggerEffortBadge: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  triggerEffortText: {
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.1,
  },
  backdrop: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.18)",
  },
  modalContainer: {
    paddingHorizontal: 20,
  },
  cardWrapper: {
    width: "100%",
    maxWidth: 440,
    alignSelf: "center",
  },
  modalCard: {
    borderRadius: 28,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 18,
  },
  dragHandleWrap: {
    alignItems: "center",
    marginBottom: 10,
  },
  dragHandle: {
    width: 38,
    height: 5,
    borderRadius: 999,
  },
  headerRow: {
    flexDirection: "row",
    alignItems: "flex-start",
    justifyContent: "space-between",
    marginBottom: 18,
    gap: 12,
  },
  headerTextColumn: {
    flex: 1,
  },
  headerTitle: {
    fontSize: 22,
    fontWeight: "800",
    letterSpacing: -0.45,
  },
  headerSubtitle: {
    marginTop: 4,
    fontSize: 14,
    lineHeight: 20,
  },
  closeButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: "center",
    justifyContent: "center",
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: "700",
    letterSpacing: 1.1,
    marginBottom: 10,
  },
  effortSectionLabel: {
    marginTop: 18,
  },
  modelRowButton: {
    borderRadius: 18,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  modelRowContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  modelTextColumn: {
    flex: 1,
  },
  modelTitle: {
    fontSize: 16,
    fontWeight: "700",
    letterSpacing: -0.2,
  },
  modelSubtitle: {
    marginTop: 4,
    fontSize: 13,
    lineHeight: 18,
  },
  modelTrailing: {
    width: 24,
    alignItems: "center",
    justifyContent: "center",
  },
  modelSeparator: {
    height: 10,
  },
  effortListContent: {
    paddingRight: 4,
  },
  effortSeparator: {
    width: 8,
  },
  effortChip: {
    minHeight: 38,
    borderRadius: 19,
    borderWidth: 1,
    paddingHorizontal: 14,
    alignItems: "center",
    justifyContent: "center",
  },
  effortChipText: {
    fontSize: 14,
    fontWeight: "700",
    letterSpacing: -0.1,
  },
  helperCard: {
    marginTop: 18,
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
  },
  helperTitle: {
    fontSize: 14,
    fontWeight: "700",
    marginBottom: 4,
  },
  helperText: {
    fontSize: 13,
    lineHeight: 18,
  },
});
