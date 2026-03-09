import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as SecureStore from "expo-secure-store";
import * as Haptics from "expo-haptics";
import Constants from "expo-constants";
import MaterialIcons from "@expo/vector-icons/MaterialIcons";
import { ScreenContainer } from "@/components/screen-container";
import { GlassCard } from "@/components/glass-card";
import { useColors } from "@/hooks/use-colors";
import { useChatStore } from "@/lib/chat-store";
import { validateApiKey } from "@/lib/openai-service";
import { AppSettings, MODELS, ReasoningEffort } from "@/lib/types";

const API_KEY_STORAGE = "openai_api_key";

const SETTINGS_SECTIONS = [
  { key: "api", title: "API Configuration" },
  { key: "defaults", title: "Model Defaults" },
  { key: "appearance", title: "Appearance" },
  { key: "data", title: "Data" },
] as const;

const EFFORT_LABELS: Record<ReasoningEffort, string> = {
  none: "None",
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "xHigh",
};

const THEME_OPTIONS: Array<{ label: string; value: AppSettings["theme"] }> = [
  { label: "Light", value: "light" },
  { label: "Dark", value: "dark" },
  { label: "System", value: "system" },
];

type SectionKey = (typeof SETTINGS_SECTIONS)[number]["key"];
type Colors = ReturnType<typeof useColors>;

async function saveApiKeyToDevice(value: string): Promise<void> {
  if (Platform.OS === "web") {
    await AsyncStorage.setItem(API_KEY_STORAGE, value);
    return;
  }

  await SecureStore.setItemAsync(API_KEY_STORAGE, value);
}

async function getApiKeyFromDevice(): Promise<string | null> {
  if (Platform.OS === "web") {
    return AsyncStorage.getItem(API_KEY_STORAGE);
  }

  return SecureStore.getItemAsync(API_KEY_STORAGE);
}

async function deleteApiKeyFromDevice(): Promise<void> {
  if (Platform.OS === "web") {
    await AsyncStorage.removeItem(API_KEY_STORAGE);
    return;
  }

  await SecureStore.deleteItemAsync(API_KEY_STORAGE);
}

function SelectionChip({
  colors,
  label,
  onPress,
  selected,
}: {
  colors: Colors;
  label: string;
  onPress: () => void;
  selected: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.selectionChip,
        {
          backgroundColor: selected ? colors.primary : colors.surface,
          borderColor: selected ? colors.primary : colors.border,
          opacity: pressed ? 0.84 : 1,
        },
      ]}
    >
      <Text
        style={[
          styles.selectionChipText,
          {
            color: selected ? "#FFFFFF" : colors.foreground,
          },
        ]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function SegmentedControl({
  colors,
  onChange,
  value,
}: {
  colors: Colors;
  onChange: (value: AppSettings["theme"]) => void;
  value: AppSettings["theme"];
}) {
  return (
    <View
      style={[
        styles.segmentedControl,
        {
          backgroundColor: colors.surface,
          borderColor: colors.border,
        },
      ]}
    >
      {THEME_OPTIONS.map((option) => {
        const selected = option.value === value;

        return (
          <Pressable
            key={option.value}
            accessibilityRole="button"
            onPress={() => onChange(option.value)}
            style={({ pressed }) => [
              styles.segmentedControlButton,
              {
                backgroundColor: selected ? colors.primary : "transparent",
                opacity: pressed ? 0.86 : 1,
              },
            ]}
          >
            <Text
              style={[
                styles.segmentedControlButtonText,
                {
                  color: selected ? "#FFFFFF" : colors.foreground,
                },
              ]}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export default function SettingsScreen() {
  const colors = useColors();
  const { state, dispatch } = useChatStore();

  const [apiKeyInput, setApiKeyInput] = useState("");
  const [showApiKey, setShowApiKey] = useState(false);
  const [isHydratingKey, setIsHydratingKey] = useState(true);
  const [isSavingKey, setIsSavingKey] = useState(false);
  const [validationStatus, setValidationStatus] = useState<"idle" | "success" | "error">("idle");
  const [validationMessage, setValidationMessage] = useState("");

  const appVersion = Constants.expoConfig?.version ?? "1.0.0";

  const selectedModel = useMemo(() => {
    return MODELS.find((item) => item.id === state.settings.defaultModel) ?? MODELS[0];
  }, [state.settings.defaultModel]);

  useEffect(() => {
    let isMounted = true;

    void (async () => {
      try {
        const storedApiKey = await getApiKeyFromDevice();

        if (!isMounted) {
          return;
        }

        if (storedApiKey) {
          setApiKeyInput(storedApiKey);

          if (state.settings.apiKey !== storedApiKey) {
            dispatch({
              type: "UPDATE_SETTINGS",
              settings: { apiKey: storedApiKey },
            });
          }
        } else if (state.settings.apiKey) {
          setApiKeyInput(state.settings.apiKey);
        }
      } catch {
        if (isMounted && state.settings.apiKey) {
          setApiKeyInput(state.settings.apiKey);
        }
      } finally {
        if (isMounted) {
          setIsHydratingKey(false);
        }
      }
    })();

    return () => {
      isMounted = false;
    };
  }, [dispatch, state.settings.apiKey]);

  const triggerLightHaptic = useCallback(() => {
    if (Platform.OS !== "web") {
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }
  }, []);

  const handleSaveApiKey = useCallback(async () => {
    const trimmed = apiKeyInput.trim();

    if (!trimmed) {
      return;
    }

    setIsSavingKey(true);
    setValidationStatus("idle");
    setValidationMessage("");

    const result = await validateApiKey(trimmed);

    if (result.valid) {
      await saveApiKeyToDevice(trimmed);
      dispatch({
        type: "UPDATE_SETTINGS",
        settings: { apiKey: trimmed },
      });
      setValidationStatus("success");
      setValidationMessage("API key saved and verified.");
      if (Platform.OS !== "web") {
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      }
    } else {
      setValidationStatus("error");
      setValidationMessage(result.error ?? "Unable to validate API key.");
      if (Platform.OS !== "web") {
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      }
    }

    setIsSavingKey(false);
  }, [apiKeyInput, dispatch]);

  const handleRemoveApiKey = useCallback(() => {
    const performRemove = async () => {
      await deleteApiKeyFromDevice();
      setApiKeyInput("");
      setValidationStatus("idle");
      setValidationMessage("");
      dispatch({
        type: "UPDATE_SETTINGS",
        settings: { apiKey: "" },
      });

      if (Platform.OS !== "web") {
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      }
    };

    if (Platform.OS === "web") {
      const confirmFn = (
        globalThis as typeof globalThis & {
          confirm?: (message?: string) => boolean;
        }
      ).confirm;

      if (confirmFn?.("Remove the saved API key?")) {
        void performRemove();
      }
      return;
    }

    Alert.alert("Remove API Key", "Remove the saved API key from this device?", [
      {
        text: "Cancel",
        style: "cancel",
      },
      {
        text: "Remove",
        style: "destructive",
        onPress: () => {
          void performRemove();
        },
      },
    ]);
  }, [dispatch]);

  const handleDefaultModelChange = useCallback(
    (modelId: (typeof MODELS)[number]["id"]) => {
      triggerLightHaptic();

      const selected = MODELS.find((item) => item.id === modelId) ?? MODELS[0];
      const nextEffort = selected.reasoningEfforts.includes(state.settings.defaultEffort)
        ? state.settings.defaultEffort
        : selected.defaultEffort;

      dispatch({
        type: "UPDATE_SETTINGS",
        settings: {
          defaultModel: selected.id,
          defaultEffort: nextEffort,
        },
      });
    },
    [dispatch, state.settings.defaultEffort, triggerLightHaptic]
  );

  const handleDefaultEffortChange = useCallback(
    (effort: ReasoningEffort) => {
      triggerLightHaptic();
      dispatch({
        type: "UPDATE_SETTINGS",
        settings: { defaultEffort: effort },
      });
    },
    [dispatch, triggerLightHaptic]
  );

  const handleThemeChange = useCallback(
    (theme: AppSettings["theme"]) => {
      triggerLightHaptic();
      dispatch({
        type: "UPDATE_SETTINGS",
        settings: { theme },
      });
    },
    [dispatch, triggerLightHaptic]
  );

  const handleClearAllConversations = useCallback(() => {
    const performClear = () => {
      dispatch({ type: "CLEAR_ALL_CONVERSATIONS" });

      if (Platform.OS !== "web") {
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      }
    };

    if (Platform.OS === "web") {
      const confirmFn = (
        globalThis as typeof globalThis & {
          confirm?: (message?: string) => boolean;
        }
      ).confirm;

      if (confirmFn?.("Clear all conversations? This cannot be undone.")) {
        performClear();
      }
      return;
    }

    Alert.alert("Clear All Conversations", "This will permanently delete every conversation.", [
      {
        text: "Cancel",
        style: "cancel",
      },
      {
        text: "Clear All",
        style: "destructive",
        onPress: performClear,
      },
    ]);
  }, [dispatch]);

  const renderSection = useCallback(
    ({ item }: { item: { key: SectionKey; title: string } }) => {
      if (item.key === "api") {
        return (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.muted }]}>{item.title}</Text>
            <GlassCard
              style={[
                styles.sectionCard,
                {
                  borderColor: colors.border,
                  borderWidth: StyleSheet.hairlineWidth,
                },
              ]}
            >
              <Text style={[styles.sectionDescription, { color: colors.muted }]}>
                Save your OpenAI API key locally on this device. On web, the key is stored in browser
                storage.
              </Text>

              <View
                style={[
                  styles.apiInputWrap,
                  {
                    backgroundColor: colors.surface,
                    borderColor: colors.border,
                  },
                ]}
              >
                <TextInput
                  autoCapitalize="none"
                  autoCorrect={false}
                  autoComplete="off"
                  editable={!isHydratingKey && !isSavingKey}
                  placeholder="sk-..."
                  placeholderTextColor={colors.muted}
                  secureTextEntry={!showApiKey}
                  spellCheck={false}
                  style={[styles.apiInput, { color: colors.foreground }]}
                  value={apiKeyInput}
                  onChangeText={(value) => {
                    setApiKeyInput(value);
                    if (validationStatus !== "idle") {
                      setValidationStatus("idle");
                      setValidationMessage("");
                    }
                  }}
                />
                <Pressable
                  accessibilityLabel={showApiKey ? "Hide API key" : "Show API key"}
                  onPress={() => setShowApiKey((current) => !current)}
                  style={({ pressed }) => [
                    styles.apiIconButton,
                    {
                      opacity: pressed ? 0.72 : 1,
                    },
                  ]}
                >
                  <MaterialIcons
                    name={showApiKey ? "visibility-off" : "visibility"}
                    size={20}
                    color={colors.muted}
                  />
                </Pressable>
              </View>

              {isHydratingKey ? (
                <View style={styles.statusRow}>
                  <ActivityIndicator size="small" color={colors.primary} />
                  <Text style={[styles.statusText, { color: colors.muted }]}>Loading saved key…</Text>
                </View>
              ) : null}

              {validationStatus === "success" ? (
                <View style={styles.statusRow}>
                  <MaterialIcons name="check-circle" size={16} color={colors.success} />
                  <Text style={[styles.statusText, { color: colors.success }]}>{validationMessage}</Text>
                </View>
              ) : null}

              {validationStatus === "error" ? (
                <View style={styles.statusRow}>
                  <MaterialIcons name="error-outline" size={16} color={colors.error} />
                  <Text style={[styles.statusText, { color: colors.error }]}>{validationMessage}</Text>
                </View>
              ) : null}

              <View style={styles.actionRow}>
                <Pressable
                  accessibilityRole="button"
                  disabled={isSavingKey || apiKeyInput.trim().length === 0}
                  onPress={() => {
                    void handleSaveApiKey();
                  }}
                  style={({ pressed }) => [
                    styles.primaryActionButton,
                    {
                      backgroundColor: colors.primary,
                      opacity:
                        pressed && apiKeyInput.trim().length > 0 && !isSavingKey
                          ? 0.84
                          : isSavingKey || apiKeyInput.trim().length === 0
                            ? 0.45
                            : 1,
                    },
                  ]}
                >
                  <Text style={styles.primaryActionButtonText}>
                    {isSavingKey ? "Validating…" : "Save API Key"}
                  </Text>
                </Pressable>

                {state.settings.apiKey ? (
                  <Pressable
                    accessibilityRole="button"
                    onPress={handleRemoveApiKey}
                    style={({ pressed }) => [
                      styles.secondaryActionButton,
                      {
                        borderColor: colors.error,
                        opacity: pressed ? 0.78 : 1,
                      },
                    ]}
                  >
                    <Text style={[styles.secondaryActionButtonText, { color: colors.error }]}>
                      Remove
                    </Text>
                  </Pressable>
                ) : null}
              </View>
            </GlassCard>
          </View>
        );
      }

      if (item.key === "defaults") {
        return (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.muted }]}>{item.title}</Text>
            <GlassCard
              style={[
                styles.sectionCard,
                {
                  borderColor: colors.border,
                  borderWidth: StyleSheet.hairlineWidth,
                },
              ]}
            >
              <Text style={[styles.fieldLabel, { color: colors.muted }]}>Default Model</Text>
              <View style={styles.chipWrap}>
                {MODELS.map((model) => (
                  <SelectionChip
                    key={model.id}
                    colors={colors}
                    label={model.label}
                    selected={state.settings.defaultModel === model.id}
                    onPress={() => handleDefaultModelChange(model.id)}
                  />
                ))}
              </View>

              <Text style={[styles.inlineDescription, { color: colors.muted }]}>
                {selectedModel.label} supports {selectedModel.reasoningEfforts.length} reasoning levels.
              </Text>

              <Text style={[styles.fieldLabel, styles.fieldLabelTop, { color: colors.muted }]}>
                Default Effort
              </Text>
              <View style={styles.chipWrap}>
                {selectedModel.reasoningEfforts.map((effort) => (
                  <SelectionChip
                    key={effort}
                    colors={colors}
                    label={EFFORT_LABELS[effort]}
                    selected={state.settings.defaultEffort === effort}
                    onPress={() => handleDefaultEffortChange(effort)}
                  />
                ))}
              </View>
            </GlassCard>
          </View>
        );
      }

      if (item.key === "appearance") {
        return (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.muted }]}>{item.title}</Text>
            <GlassCard
              style={[
                styles.sectionCard,
                {
                  borderColor: colors.border,
                  borderWidth: StyleSheet.hairlineWidth,
                },
              ]}
            >
              <Text style={[styles.fieldLabel, { color: colors.muted }]}>Theme</Text>
              <SegmentedControl
                colors={colors}
                onChange={handleThemeChange}
                value={state.settings.theme}
              />
              <Text style={[styles.inlineDescription, { color: colors.muted }]}>
                System follows your device appearance automatically.
              </Text>
            </GlassCard>
          </View>
        );
      }

      return (
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>{item.title}</Text>
          <GlassCard
            style={[
              styles.sectionCard,
              {
                borderColor: colors.border,
                borderWidth: StyleSheet.hairlineWidth,
              },
            ]}
          >
            <View style={styles.dataRow}>
              <View style={styles.dataRowText}>
                <Text style={[styles.dataTitle, { color: colors.foreground }]}>Saved Conversations</Text>
                <Text style={[styles.dataSubtitle, { color: colors.muted }]}>
                  Stored locally on this device.
                </Text>
              </View>
              <Text style={[styles.dataValue, { color: colors.foreground }]}>
                {state.conversations.length}
              </Text>
            </View>

            <Pressable
              accessibilityRole="button"
              onPress={handleClearAllConversations}
              style={({ pressed }) => [
                styles.dangerButton,
                {
                  backgroundColor: `${colors.error}10`,
                  borderColor: `${colors.error}22`,
                  opacity: pressed ? 0.82 : 1,
                },
              ]}
            >
              <MaterialIcons name="delete-outline" size={18} color={colors.error} />
              <Text style={[styles.dangerButtonText, { color: colors.error }]}>
                Clear All Conversations
              </Text>
            </Pressable>
          </GlassCard>
        </View>
      );
    },
    [
      colors,
      handleClearAllConversations,
      handleDefaultEffortChange,
      handleDefaultModelChange,
      handleRemoveApiKey,
      handleSaveApiKey,
      handleThemeChange,
      isHydratingKey,
      isSavingKey,
      selectedModel,
      state.conversations.length,
      state.settings.apiKey,
      state.settings.defaultEffort,
      state.settings.defaultModel,
      state.settings.theme,
      validationMessage,
      validationStatus,
      apiKeyInput,
      showApiKey,
    ]
  );

  const footer = useMemo(() => {
    return (
      <View style={styles.footer}>
        <Text style={[styles.footerVersion, { color: colors.muted }]}>Liquid Glass Chat v{appVersion}</Text>
      </View>
    );
  }, [appVersion, colors.muted]);

  return (
    <ScreenContainer>
      <View style={[styles.screen, { backgroundColor: colors.background }]}>
        <KeyboardAvoidingView
          behavior={Platform.OS === "ios" ? "padding" : undefined}
          keyboardVerticalOffset={0}
          style={styles.flex}
        >
          <FlatList
            contentContainerStyle={styles.listContent}
            data={SETTINGS_SECTIONS}
            ItemSeparatorComponent={() => <View style={styles.separator} />}
            keyExtractor={(item) => item.key}
            keyboardShouldPersistTaps="handled"
            ListFooterComponent={footer}
            ListHeaderComponent={
              <View style={styles.headerWrap}>
                <GlassCard
                  style={[
                    styles.headerCard,
                    {
                      borderColor: colors.border,
                      borderWidth: StyleSheet.hairlineWidth,
                    },
                  ]}
                >
                  <Text style={[styles.headerTitle, { color: colors.foreground }]}>Settings</Text>
                  <Text style={[styles.headerSubtitle, { color: colors.muted }]}>
                    Configure your API key, default model behavior, appearance, and local app data.
                  </Text>
                </GlassCard>
              </View>
            }
            renderItem={renderSection}
            showsVerticalScrollIndicator={false}
          />
        </KeyboardAvoidingView>
      </View>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  flex: {
    flex: 1,
  },
  listContent: {
    paddingBottom: 28,
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  headerWrap: {
    marginBottom: 16,
  },
  headerCard: {
    borderRadius: 24,
    paddingHorizontal: 18,
    paddingVertical: 18,
  },
  headerTitle: {
    fontSize: 30,
    fontWeight: "800",
    letterSpacing: -0.6,
  },
  headerSubtitle: {
    fontSize: 14,
    lineHeight: 21,
    marginTop: 6,
  },
  separator: {
    height: 18,
  },
  section: {
    gap: 8,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: "700",
    letterSpacing: 0.2,
    marginLeft: 4,
  },
  sectionCard: {
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  sectionDescription: {
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 14,
  },
  apiInputWrap: {
    alignItems: "center",
    borderRadius: 16,
    borderWidth: 1,
    flexDirection: "row",
    minHeight: 52,
    paddingLeft: 14,
    paddingRight: 8,
  },
  apiInput: {
    flex: 1,
    fontSize: 15,
    minHeight: 48,
    paddingVertical: 10,
  },
  apiIconButton: {
    alignItems: "center",
    borderRadius: 18,
    height: 36,
    justifyContent: "center",
    width: 36,
  },
  statusRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 8,
    marginTop: 12,
  },
  statusText: {
    flex: 1,
    fontSize: 13,
    lineHeight: 18,
  },
  actionRow: {
    flexDirection: "row",
    gap: 10,
    marginTop: 14,
  },
  primaryActionButton: {
    alignItems: "center",
    borderRadius: 16,
    flex: 1,
    justifyContent: "center",
    minHeight: 48,
    paddingHorizontal: 16,
  },
  primaryActionButtonText: {
    color: "#FFFFFF",
    fontSize: 15,
    fontWeight: "700",
  },
  secondaryActionButton: {
    alignItems: "center",
    borderRadius: 16,
    borderWidth: 1,
    justifyContent: "center",
    minHeight: 48,
    paddingHorizontal: 16,
  },
  secondaryActionButtonText: {
    fontSize: 15,
    fontWeight: "700",
  },
  fieldLabel: {
    fontSize: 12,
    fontWeight: "700",
    letterSpacing: 0.3,
    textTransform: "uppercase",
  },
  fieldLabelTop: {
    marginTop: 16,
  },
  chipWrap: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
    marginTop: 10,
  },
  selectionChip: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  selectionChipText: {
    fontSize: 14,
    fontWeight: "700",
  },
  inlineDescription: {
    fontSize: 13,
    lineHeight: 18,
    marginTop: 10,
  },
  segmentedControl: {
    borderRadius: 16,
    borderWidth: 1,
    flexDirection: "row",
    marginTop: 10,
    padding: 4,
  },
  segmentedControlButton: {
    alignItems: "center",
    borderRadius: 12,
    flex: 1,
    justifyContent: "center",
    minHeight: 40,
    paddingHorizontal: 12,
  },
  segmentedControlButtonText: {
    fontSize: 14,
    fontWeight: "700",
  },
  dataRow: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  dataRowText: {
    flex: 1,
    paddingRight: 12,
  },
  dataTitle: {
    fontSize: 16,
    fontWeight: "700",
  },
  dataSubtitle: {
    fontSize: 13,
    marginTop: 4,
  },
  dataValue: {
    fontSize: 24,
    fontWeight: "800",
    letterSpacing: -0.4,
  },
  dangerButton: {
    alignItems: "center",
    borderRadius: 16,
    borderWidth: 1,
    flexDirection: "row",
    gap: 8,
    justifyContent: "center",
    marginTop: 16,
    minHeight: 48,
    paddingHorizontal: 16,
  },
  dangerButtonText: {
    fontSize: 15,
    fontWeight: "700",
  },
  footer: {
    alignItems: "center",
    paddingBottom: 8,
    paddingTop: 20,
  },
  footerVersion: {
    fontSize: 13,
    fontWeight: "600",
  },
});
