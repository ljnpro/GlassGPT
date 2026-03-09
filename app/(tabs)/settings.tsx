import React, { useState, useCallback, useEffect } from 'react';
import { View, Text, TextInput, ScrollView, StyleSheet, Platform, Pressable, Alert, Switch } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useColors } from '@/hooks/use-colors';
import { useChatStore } from '@/lib/chat-store';
import { saveApiKey, getApiKey, deleteApiKey } from '@/lib/secure-storage';
import { validateApiKey } from '@/lib/openai-service';
import { MODELS, ModelId, ReasoningEffort } from '@/lib/types';
import { GlassCard } from '@/components/glass-card';

const EFFORT_LABELS: Record<ReasoningEffort, string> = {
  none: 'None',
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  xhigh: 'xHigh',
};

export default function SettingsScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const { state, dispatch } = useChatStore();
  const [apiKeyInput, setApiKeyInput] = useState('');
  const [showKey, setShowKey] = useState(false);
  const [isValidating, setIsValidating] = useState(false);
  const [validationStatus, setValidationStatus] = useState<'idle' | 'valid' | 'invalid'>('idle');

  useEffect(() => {
    (async () => {
      const key = await getApiKey();
      if (key) {
        setApiKeyInput(key);
        dispatch({ type: 'UPDATE_SETTINGS', settings: { apiKey: key } });
      }
    })();
  }, []);

  const handleSaveKey = useCallback(async () => {
    const key = apiKeyInput.trim();
    if (!key) return;

    setIsValidating(true);
    setValidationStatus('idle');

    const result = await validateApiKey(key);
    if (result.valid) {
      await saveApiKey(key);
      dispatch({ type: 'UPDATE_SETTINGS', settings: { apiKey: key } });
      setValidationStatus('valid');
      if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } else {
      setValidationStatus('invalid');
      if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
    }
    setIsValidating(false);
  }, [apiKeyInput, dispatch]);

  const handleDeleteKey = useCallback(async () => {
    const doDelete = async () => {
      await deleteApiKey();
      setApiKeyInput('');
      dispatch({ type: 'UPDATE_SETTINGS', settings: { apiKey: '' } });
      setValidationStatus('idle');
      if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    };

    if (Platform.OS === 'web') {
      if (confirm('Remove API key?')) doDelete();
    } else {
      Alert.alert('Remove API Key', 'Are you sure?', [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Remove', style: 'destructive', onPress: doDelete },
      ]);
    }
  }, [dispatch]);

  const handleClearConversations = useCallback(() => {
    const doClear = () => {
      dispatch({ type: 'CLEAR_ALL_CONVERSATIONS' });
      if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    };

    if (Platform.OS === 'web') {
      if (confirm('Delete all conversations? This cannot be undone.')) doClear();
    } else {
      Alert.alert('Clear All Conversations', 'This cannot be undone.', [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete All', style: 'destructive', onPress: doClear },
      ]);
    }
  }, [dispatch]);

  const currentModelConfig = MODELS.find((m) => m.id === state.settings.defaultModel) || MODELS[1];

  return (
    <View style={[styles.screen, { backgroundColor: colors.background }]}>
      <View style={[styles.header, { paddingTop: insets.top + 8 }]}>
        <GlassCard style={styles.headerGlass}>
          <Text style={[styles.headerTitle, { color: colors.foreground }]}>Settings</Text>
        </GlassCard>
      </View>

      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        {/* API Key Section */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>OPENAI API KEY</Text>
          <GlassCard style={styles.card}>
            <View style={[styles.apiKeyRow, { borderColor: colors.border }]}>
              <TextInput
                style={[styles.apiKeyInput, { color: colors.foreground }]}
                placeholder="sk-..."
                placeholderTextColor={colors.muted}
                value={apiKeyInput}
                onChangeText={(t) => {
                  setApiKeyInput(t);
                  setValidationStatus('idle');
                }}
                secureTextEntry={!showKey}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <Pressable
                onPress={() => setShowKey(!showKey)}
                style={({ pressed }) => [{ opacity: pressed ? 0.6 : 1, padding: 8 }]}
              >
                <MaterialIcons name={showKey ? 'visibility-off' : 'visibility'} size={20} color={colors.muted} />
              </Pressable>
            </View>

            {validationStatus === 'valid' && (
              <View style={styles.statusRow}>
                <MaterialIcons name="check-circle" size={16} color={colors.success} />
                <Text style={{ color: colors.success, fontSize: 13 }}>API key is valid</Text>
              </View>
            )}
            {validationStatus === 'invalid' && (
              <View style={styles.statusRow}>
                <MaterialIcons name="error" size={16} color={colors.error} />
                <Text style={{ color: colors.error, fontSize: 13 }}>Invalid API key</Text>
              </View>
            )}

            <View style={styles.btnRow}>
              <Pressable
                onPress={handleSaveKey}
                disabled={isValidating || !apiKeyInput.trim()}
                style={({ pressed }) => [
                  styles.saveBtn,
                  {
                    backgroundColor: colors.primary,
                    opacity: pressed ? 0.8 : isValidating || !apiKeyInput.trim() ? 0.5 : 1,
                  },
                ]}
              >
                <Text style={styles.saveBtnText}>
                  {isValidating ? 'Validating...' : 'Save & Validate'}
                </Text>
              </Pressable>
              {state.settings.apiKey && (
                <Pressable
                  onPress={handleDeleteKey}
                  style={({ pressed }) => [styles.deleteBtn, { borderColor: colors.error, opacity: pressed ? 0.7 : 1 }]}
                >
                  <Text style={{ color: colors.error, fontSize: 14, fontWeight: '600' }}>Remove</Text>
                </Pressable>
              )}
            </View>
          </GlassCard>
        </View>

        {/* Default Model */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>DEFAULT MODEL</Text>
          <GlassCard style={styles.card}>
            <View style={styles.chipRow}>
              {MODELS.map((m) => (
                <Pressable
                  key={m.id}
                  onPress={() => {
                    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                    dispatch({ type: 'UPDATE_SETTINGS', settings: { defaultModel: m.id } });
                    if (!m.reasoningEfforts.includes(state.settings.defaultEffort)) {
                      dispatch({ type: 'UPDATE_SETTINGS', settings: { defaultEffort: m.defaultEffort } });
                    }
                  }}
                  style={({ pressed }) => [
                    styles.chip,
                    {
                      backgroundColor: state.settings.defaultModel === m.id ? colors.primary : colors.surface,
                      borderColor: state.settings.defaultModel === m.id ? colors.primary : colors.border,
                      opacity: pressed ? 0.8 : 1,
                    },
                  ]}
                >
                  <Text
                    style={{
                      color: state.settings.defaultModel === m.id ? '#FFFFFF' : colors.foreground,
                      fontWeight: '600',
                      fontSize: 14,
                    }}
                  >
                    {m.label}
                  </Text>
                </Pressable>
              ))}
            </View>
          </GlassCard>
        </View>

        {/* Default Reasoning Effort */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>DEFAULT REASONING EFFORT</Text>
          <GlassCard style={styles.card}>
            <View style={styles.chipRow}>
              {currentModelConfig.reasoningEfforts.map((e) => (
                <Pressable
                  key={e}
                  onPress={() => {
                    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                    dispatch({ type: 'UPDATE_SETTINGS', settings: { defaultEffort: e } });
                  }}
                  style={({ pressed }) => [
                    styles.chip,
                    {
                      backgroundColor: state.settings.defaultEffort === e ? colors.primary : colors.surface,
                      borderColor: state.settings.defaultEffort === e ? colors.primary : colors.border,
                      opacity: pressed ? 0.8 : 1,
                    },
                  ]}
                >
                  <Text
                    style={{
                      color: state.settings.defaultEffort === e ? '#FFFFFF' : colors.foreground,
                      fontWeight: '600',
                      fontSize: 13,
                    }}
                  >
                    {EFFORT_LABELS[e]}
                  </Text>
                </Pressable>
              ))}
            </View>
          </GlassCard>
        </View>

        {/* Data */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>DATA</Text>
          <GlassCard style={styles.card}>
            <Pressable
              onPress={handleClearConversations}
              style={({ pressed }) => [styles.dangerRow, { opacity: pressed ? 0.7 : 1 }]}
            >
              <MaterialIcons name="delete-outline" size={22} color={colors.error} />
              <Text style={{ color: colors.error, fontSize: 15, fontWeight: '500' }}>
                Clear All Conversations
              </Text>
            </Pressable>
          </GlassCard>
        </View>

        {/* About */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.muted }]}>ABOUT</Text>
          <GlassCard style={styles.card}>
            <View style={styles.aboutRow}>
              <Text style={{ color: colors.foreground, fontSize: 15 }}>Liquid Glass Chat</Text>
              <Text style={{ color: colors.muted, fontSize: 14 }}>v1.0.0</Text>
            </View>
            <Text style={{ color: colors.muted, fontSize: 13, lineHeight: 18, marginTop: 8 }}>
              A premium ChatGPT frontend with iOS 26 Liquid Glass design. Uses your own OpenAI API key for GPT-5.4 and GPT-5.4 Pro models.
            </Text>
          </GlassCard>
        </View>

        <View style={{ height: 100 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  header: {
    zIndex: 10,
  },
  headerGlass: {
    borderRadius: 0,
    paddingHorizontal: 20,
    paddingVertical: 12,
  },
  headerTitle: {
    fontSize: 32,
    fontWeight: '800',
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
    marginBottom: 8,
    marginLeft: 4,
  },
  card: {
    padding: 16,
    gap: 12,
  },
  apiKeyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 12,
  },
  apiKeyInput: {
    flex: 1,
    fontSize: 15,
    paddingVertical: 10,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  btnRow: {
    flexDirection: 'row',
    gap: 10,
  },
  saveBtn: {
    flex: 1,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
  },
  saveBtnText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '600',
  },
  deleteBtn: {
    borderRadius: 12,
    borderWidth: 1,
    paddingHorizontal: 16,
    paddingVertical: 12,
    alignItems: 'center',
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  chip: {
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  dangerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 4,
  },
  aboutRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});
